#include <signal.h>
#include <stdio.h>
#include <unistd.h>
static volatile sig_atomic_t stopping = 0;
static void stop(int signal_number) { (void)signal_number; stopping = 1; }
int main(void) {
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    puts("example.residueguard.fixture.iso01 ready");
    fflush(stdout);
    for (unsigned seconds = 0; !stopping && seconds < 120; ++seconds) sleep(1);
    return 0;
}
