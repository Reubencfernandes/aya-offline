#ifndef LLAMA_CPP_BRIDGE_H
#define LLAMA_CPP_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool llama_init_model(
    const char* model_path,
    int32_t n_threads,
    int32_t n_gpu_layers,
    int32_t context_size,
    int32_t batch_size,
    bool use_gpu,
    bool verbose
);

bool llama_generate(
    const char* prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    int32_t max_tokens,
    float repeat_penalty,
    const char* stop_sequences,
    char* output,
    int32_t output_size,
    int32_t* tokens_generated
);

void llama_generate_stream_init(
    const char* prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    int32_t max_tokens,
    float repeat_penalty,
    const char* stop_sequences
);

bool llama_generate_stream_next(char* output, int32_t output_size);
void llama_generate_stream_end(void);

void llama_get_model_info(
    int64_t* n_params,
    int32_t* n_layers,
    int32_t* context_size
);

void llama_cpp_bridge_free_model(void);
void llama_stop_generation(void);
const char* llama_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
