/* No-op SanCov callbacks for the sanitizer-less standalone reproducer (the instrumented project objects
   still reference them, and without ASan/UBSan there is no runtime to provide them). */
#include <stdint.h>
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) { (void)start; (void)stop; }
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) { (void)guard; }
