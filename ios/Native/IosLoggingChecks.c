#include <stdint.h>
#include <stdio.h>

extern int32_t ryu_ios_logging_check(void);

int main(void) {
    int status = ryu_ios_logging_check();
    if (status != 0) { fprintf(stderr, "FAIL iOS console regression: %d\n", status); return 1; }
    puts("PASS: real iOS BCL rejects terminal colours; async/direct logger and disposal survive.");
    return 0;
}
