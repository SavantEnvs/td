// Silences td's LOG(ERROR) chatter (which would otherwise write to stderr on every exec).
#include "td/utils/logging.h"

extern "C" int LLVMFuzzerInitialize(int *, char ***) {
  SET_VERBOSITY_LEVEL(VERBOSITY_NAME(FATAL));
  return 0;
}
