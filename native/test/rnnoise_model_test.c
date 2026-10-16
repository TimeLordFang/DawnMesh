#include "rnnoise.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
  assert(rnnoise_model_from_file(NULL) == NULL);
  assert(rnnoise_model_from_filename("/dev/null/dawnmesh-model") == NULL);

  FILE *file = tmpfile();
  assert(file != NULL);
  assert(rnnoise_model_from_file(file) == NULL);  /* Empty model. */
  assert(fwrite("test", 1, 4, file) == 4);
  assert(fflush(file) == 0);
  RNNModel *model = rnnoise_model_from_file(file);
  assert(model != NULL);
  rnnoise_model_free(model);
  assert(fseek(file, 0, SEEK_SET) == 0);  /* The caller still owns FILE. */
  assert(fgetc(file) == 't');

  /* Sparse file: exercise the >INT_MAX guard without allocating gigabytes. */
  assert(fseek(file, (long)INT_MAX, SEEK_SET) == 0);
  assert(fputc(0, file) != EOF);
  assert(fflush(file) == 0);
  assert(rnnoise_model_from_file(file) == NULL);
  fclose(file);

  int descriptors[2];
  assert(pipe(descriptors) == 0);
  file = fdopen(descriptors[0], "rb");
  assert(file != NULL);
  assert(rnnoise_model_from_file(file) == NULL);  /* Non-seekable stream. */
  fclose(file);
  close(descriptors[1]);
  puts("RNNoise model file bounds and ownership passed");
  return 0;
}
