int pointer_load(int *p) {
  return *p;
}

int pointer_roundtrip(int *p, int input) {
  *p = input;
  return *p;
}

int main(void) {
  int x = 0;
  pointer_roundtrip(&x, 99);
  return pointer_load(&x);  /* expected: 99 */
}




