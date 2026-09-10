#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void allocate_unreachable_blocks(void) {
    for (int index = 0; index < 128; index++) {
        void *block = malloc(16 * 1024);
        if (block == NULL) {
            perror("malloc");
            exit(2);
        }

        memset(block, index, 16 * 1024);
    }
}

int main(void) {
    printf("leaky_process pid=%d\n", getpid());
    fflush(stdout);

    for (int iteration = 0; iteration < 60; iteration++) {
        allocate_unreachable_blocks();
        usleep(250000);
    }

    sleep(30);
    return 0;
}
