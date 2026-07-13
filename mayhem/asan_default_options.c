/* ikos-analyzer is an allocate-and-exit batch tool: analysis results are the
 * output and memory is reclaimed by process exit. Exit-time leak reports would
 * drown real ASan/UBSan defects, so bake detect_leaks=0 into the binary
 * (Mayhem owns ASAN_OPTIONS at run time). */
const char* __asan_default_options(void) {
  return "detect_leaks=0";
}
