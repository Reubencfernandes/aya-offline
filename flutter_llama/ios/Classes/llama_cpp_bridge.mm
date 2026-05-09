/*
 * Flutter Llama - llama.cpp Bridge for iOS
 * 
 * This file provides a C++ bridge between Swift and llama.cpp
 * Updated for latest llama.cpp API
 */

#import <Foundation/Foundation.h>
#import "llama_cpp_bridge.h"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>
#include <mutex>

// Include llama.cpp headers
#include "../../llama.cpp/include/llama.h"

// Global state
static llama_model* g_model = nullptr;
static llama_context* g_context = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::mutex g_mutex;
static std::mutex g_log_mutex;
static bool g_should_stop = false;
static bool g_stream_active = false;
static int32_t g_stream_max_tokens = 0;
static int32_t g_stream_tokens_generated = 0;
static std::string g_stream_output;
static size_t g_stream_emitted_chars = 0;
static std::vector<std::string> g_stream_stop_sequences;
static std::string g_last_error;

static void llama_bridge_clear_last_error() {
    std::lock_guard<std::mutex> lock(g_log_mutex);
    g_last_error.clear();
}

static void llama_bridge_append_last_error(const char* text) {
    if (!text) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_log_mutex);
    g_last_error.append(text);
    if (g_last_error.size() > 4096) {
        g_last_error.erase(0, g_last_error.size() - 4096);
    }
}

static void llama_bridge_log_callback(enum ggml_log_level level, const char* text, void* user_data) {
    (void) user_data;
    if (!text) {
        return;
    }

    if (level == GGML_LOG_LEVEL_WARN ||
        level == GGML_LOG_LEVEL_ERROR ||
        level == GGML_LOG_LEVEL_CONT) {
        llama_bridge_append_last_error(text);
    }

    if (level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR) {
        NSLog(@"[llama.cpp] %s", text);
    }
}

static std::vector<std::string> llama_bridge_parse_stop_sequences(const char* joined) {
    std::vector<std::string> stop_sequences;
    if (!joined || joined[0] == '\0') {
        return stop_sequences;
    }

    const std::string payload(joined);
    size_t start = 0;
    while (start <= payload.size()) {
        const size_t end = payload.find('\x1F', start);
        const std::string item = payload.substr(
            start,
            end == std::string::npos ? std::string::npos : end - start
        );
        if (!item.empty()) {
            stop_sequences.push_back(item);
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }

    return stop_sequences;
}

static size_t llama_bridge_find_stop_sequence(
    const std::string& text,
    const std::vector<std::string>& stop_sequences
) {
    size_t first_match = std::string::npos;
    for (const std::string& stop_sequence : stop_sequences) {
        const size_t match = text.find(stop_sequence);
        if (match != std::string::npos &&
            (first_match == std::string::npos || match < first_match)) {
            first_match = match;
        }
    }
    return first_match;
}

static size_t llama_bridge_stop_prefix_holdback(
    const std::string& pending,
    const std::vector<std::string>& stop_sequences
) {
    size_t holdback = 0;
    for (const std::string& stop_sequence : stop_sequences) {
        const size_t max_len = std::min(pending.size(), stop_sequence.size() - 1);
        for (size_t len = 1; len <= max_len; len++) {
            if (pending.compare(pending.size() - len, len, stop_sequence, 0, len) == 0) {
                holdback = std::max(holdback, len);
            }
        }
    }
    return holdback;
}

static void llama_bridge_reset_stream_state() {
    g_stream_active = false;
    g_stream_max_tokens = 0;
    g_stream_tokens_generated = 0;
    g_stream_output.clear();
    g_stream_emitted_chars = 0;
    g_stream_stop_sequences.clear();
}

static bool llama_bridge_emit_stream_output(
    char* output,
    int32_t output_size,
    bool flush
) {
    if (!output || output_size <= 0) {
        return false;
    }

    output[0] = '\0';

    size_t target_end = g_stream_output.size();
    const size_t stop_pos = llama_bridge_find_stop_sequence(
        g_stream_output,
        g_stream_stop_sequences
    );

    if (stop_pos != std::string::npos) {
        target_end = stop_pos;
        g_should_stop = true;
    } else if (!flush && target_end > g_stream_emitted_chars) {
        const std::string pending = g_stream_output.substr(g_stream_emitted_chars);
        const size_t holdback = llama_bridge_stop_prefix_holdback(
            pending,
            g_stream_stop_sequences
        );
        target_end -= holdback;
    }

    if (target_end <= g_stream_emitted_chars) {
        return false;
    }

    const size_t available = target_end - g_stream_emitted_chars;
    const size_t copy_len = std::min(available, static_cast<size_t>(output_size - 1));
    memcpy(output, g_stream_output.data() + g_stream_emitted_chars, copy_len);
    output[copy_len] = '\0';
    g_stream_emitted_chars += copy_len;
    return copy_len > 0;
}

extern "C" {

// Initialize and load model
bool llama_init_model(
    const char* model_path,
    int32_t n_threads,
    int32_t n_gpu_layers,
    int32_t context_size,
    int32_t batch_size,
    bool use_gpu,
    bool verbose
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    NSLog(@"[llama_cpp_bridge] Initializing model: %s", model_path);
    NSLog(@"[llama_cpp_bridge] Threads: %d, GPU layers: %d, Context: %d", 
          n_threads, n_gpu_layers, context_size);
    llama_bridge_clear_last_error();
    llama_log_set(llama_bridge_log_callback, nullptr);
    
    // Free existing model if any
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    
    // Load dynamic backends
    ggml_backend_load_all();
    
    // Set up model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = use_gpu ? n_gpu_layers : 0;
    
    // Load model
    g_model = llama_model_load_from_file(model_path, model_params);
    if (!g_model) {
        NSLog(@"[llama_cpp_bridge] Failed to load model from: %s", model_path);
        llama_bridge_append_last_error("llama_model_load_from_file returned null");
        return false;
    }
    
    // Get vocab
    g_vocab = llama_model_get_vocab(g_model);
    
    // Create context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size;
    ctx_params.n_batch = batch_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    
    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        NSLog(@"[llama_cpp_bridge] Failed to create context");
        llama_bridge_append_last_error("llama_init_from_model returned null");
        llama_model_free(g_model);
        g_model = nullptr;
        return false;
    }
    
    // Initialize sampler chain
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    g_sampler = llama_sampler_chain_init(sparams);
    
    // Add samplers
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    NSLog(@"[llama_cpp_bridge] Model loaded successfully");
    NSLog(@"[llama_cpp_bridge] Context size: %d", llama_n_ctx(g_context));
    
    return true;
}

// Generate text
bool llama_generate(
    const char* prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    int32_t max_tokens,
    float repeat_penalty,
    const char* stop_sequences_joined,
    char* output,
    int32_t output_size,
    int32_t* tokens_generated
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    (void) repeat_penalty;
    
    if (!g_model || !g_context || !g_vocab) {
        NSLog(@"[llama_cpp_bridge] Model not loaded");
        return false;
    }
    
    NSLog(@"[llama_cpp_bridge] Generating with prompt: %.50s...", prompt);
    
    std::string prompt_text(prompt);
    const std::vector<std::string> stop_sequences =
        llama_bridge_parse_stop_sequences(stop_sequences_joined);

    // Reset KV cache so each generation starts from a clean context —
    // otherwise tokens from the previous call (e.g. a translate prompt)
    // stay in the cache and bleed into the next generation (e.g. chat).
    llama_memory_clear(llama_get_memory(g_context), true);

    // Tokenize prompt
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    std::vector<llama_token> prompt_tokens(n_prompt);

    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        NSLog(@"[llama_cpp_bridge] Failed to tokenize prompt");
        return false;
    }

    // Create batch
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());

    // Decode prompt
    if (llama_decode(g_context, batch) != 0) {
        NSLog(@"[llama_cpp_bridge] Failed to decode prompt");
        return false;
    }

    // Update sampler with new parameters
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }
    
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Generate tokens
    std::string result;
    int n_gen = 0;
    int n_pos = prompt_tokens.size();
    
    g_should_stop = false;
    
    for (int i = 0; i < max_tokens; i++) {
        if (g_should_stop) {
            NSLog(@"[llama_cpp_bridge] Generation stopped by user");
            break;
        }
        
        // Sample next token
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);
        
        // Check for EOS
        if (llama_vocab_is_eog(g_vocab, new_token)) {
            NSLog(@"[llama_cpp_bridge] EOS token reached");
            break;
        }
        
        // Convert token to text
        char token_str[256] = {0};
        int n = llama_token_to_piece(g_vocab, new_token, token_str, sizeof(token_str) - 1, 0, true);
        if (n > 0) {
            token_str[n] = '\0';
            result.append(token_str);
        }

        const size_t stop_pos = llama_bridge_find_stop_sequence(result, stop_sequences);
        if (stop_pos != std::string::npos) {
            result.erase(stop_pos);
            break;
        }
        
        // Prepare for next iteration
        batch = llama_batch_get_one(&new_token, 1);
        n_pos++;
        
        if (llama_decode(g_context, batch) != 0) {
            NSLog(@"[llama_cpp_bridge] Failed to decode token");
            break;
        }
        
        n_gen++;
    }
    
    // Copy result
    size_t copy_len = std::min(result.length(), (size_t)(output_size - 1));
    memcpy(output, result.c_str(), copy_len);
    output[copy_len] = '\0';
    *tokens_generated = n_gen;
    
    NSLog(@"[llama_cpp_bridge] Generated %d tokens", n_gen);
    return true;
}

// Initialize streaming generation
void llama_generate_stream_init(
    const char* prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    int32_t max_tokens,
    float repeat_penalty,
    const char* stop_sequences_joined
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    (void) repeat_penalty;
    
    NSLog(@"[llama_cpp_bridge] Initializing stream generation");
    
    if (!g_model || !g_context || !g_vocab) {
        NSLog(@"[llama_cpp_bridge] Model not loaded");
        return;
    }
    
    g_should_stop = false;
    llama_bridge_reset_stream_state();
    g_stream_max_tokens = max_tokens;
    g_stream_stop_sequences = llama_bridge_parse_stop_sequences(stop_sequences_joined);

    std::string prompt_text(prompt);

    // Reset KV cache so each generation starts from a clean context —
    // otherwise tokens from the previous call (e.g. a translate prompt)
    // stay in the cache and bleed into the next generation (e.g. chat).
    llama_memory_clear(llama_get_memory(g_context), true);

    // Tokenize prompt
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    std::vector<llama_token> prompt_tokens(n_prompt);

    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        NSLog(@"[llama_cpp_bridge] Failed to tokenize prompt");
        return;
    }

    // Create batch
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());

    // Decode prompt
    if (llama_decode(g_context, batch) != 0) {
        NSLog(@"[llama_cpp_bridge] Failed to decode prompt");
        return;
    }
    
    // Update sampler
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }
    
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));

    g_stream_active = true;
    NSLog(@"[llama_cpp_bridge] Stream generation initialized");
}

// Get next token in stream
bool llama_generate_stream_next(
    char* output,
    int32_t output_size
) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!output || output_size <= 0) {
        return false;
    }

    output[0] = '\0';

    if (!g_stream_active) {
        return false;
    }

    if (llama_bridge_emit_stream_output(output, output_size, false)) {
        return true;
    }

    if (g_should_stop) {
        return llama_bridge_emit_stream_output(output, output_size, true);
    }

    while (g_stream_tokens_generated < g_stream_max_tokens) {
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);

        if (llama_vocab_is_eog(g_vocab, new_token)) {
            g_should_stop = true;
            break;
        }

        char token_str[256] = {0};
        int n = llama_token_to_piece(g_vocab, new_token, token_str, sizeof(token_str) - 1, 0, true);
        if (n > 0) {
            token_str[n] = '\0';
            g_stream_output.append(token_str);
        }

        if (llama_bridge_find_stop_sequence(g_stream_output, g_stream_stop_sequences) !=
            std::string::npos) {
            g_should_stop = true;
            return llama_bridge_emit_stream_output(output, output_size, true);
        }

        llama_batch batch = llama_batch_get_one(&new_token, 1);

        if (llama_decode(g_context, batch) != 0) {
            NSLog(@"[llama_cpp_bridge] Failed to decode stream token");
            g_should_stop = true;
            break;
        }

        g_stream_tokens_generated++;

        if (llama_bridge_emit_stream_output(output, output_size, false)) {
            return true;
        }
    }

    g_should_stop = true;
    return llama_bridge_emit_stream_output(output, output_size, true);
}

// End streaming generation
void llama_generate_stream_end() {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    NSLog(@"[llama_cpp_bridge] Ending stream generation");
    llama_bridge_reset_stream_state();
}

// Get model information
void llama_get_model_info(
    int64_t* n_params,
    int32_t* n_layers,
    int32_t* context_size
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_model || !g_context) {
        *n_params = 0;
        *n_layers = 0;
        *context_size = 0;
        return;
    }
    
    *n_params = llama_model_n_params(g_model);
    *n_layers = llama_model_n_layer(g_model);
    *context_size = llama_n_ctx(g_context);
}

// Free model
void llama_cpp_bridge_free_model() {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    NSLog(@"[llama_cpp_bridge] Freeing model");
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    
    g_vocab = nullptr;
    
    NSLog(@"[llama_cpp_bridge] Model freed successfully");
}

// Stop generation
void llama_stop_generation() {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    NSLog(@"[llama_cpp_bridge] Stopping generation");
    g_should_stop = true;
}

const char* llama_last_error() {
    std::lock_guard<std::mutex> lock(g_log_mutex);
    return g_last_error.c_str();
}

} // extern "C"
