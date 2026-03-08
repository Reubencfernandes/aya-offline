/* Quick test: just open gguf and print info */
#include "gguf.h"
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 2) { printf("Usage: %s <file.gguf>\n", argv[0]); return 1; }
    printf("Opening: %s\n", argv[1]);
    fflush(stdout);

    gguf_file *f = gguf_open(argv[1]);
    if (!f) { printf("FAILED\n"); return 1; }

    printf("OK! vocab=%d tensors=%d\n", f->vocab_size, f->n_tensors);

    /* Print all tensors */
    for (int i = 0; i < f->n_tensors; i++) {
        printf("  tensor[%d]: %s type=%d shape=[", i, f->tensors[i].name,
               f->tensors[i].type);
        for (int d = 0; d < f->tensors[i].n_dims; d++) {
            if (d > 0) printf(",");
            printf("%lld", (long long)f->tensors[i].shape[d]);
        }
        printf("] elements=%lld\n", (long long)f->tensors[i].n_elements);
    }

    /* Print first 5 vocab tokens */
    if (f->vocab_tokens) {
        for (int i = 0; i < 5 && i < f->vocab_size; i++) {
            printf("  token[%d]: '%s'\n", i, f->vocab_tokens[i] ? f->vocab_tokens[i] : "(null)");
        }
    }

    gguf_close(f);
    printf("Done.\n");
    return 0;
}
