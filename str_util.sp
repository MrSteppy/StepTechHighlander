#if defined _STR_UTIL_H
  #endinput
#endif
#define _STR_UTIL_H

enum _elemBufSize {
  EBS_int = 10,
}

int append_str(char[] dest, int destSize, const char[] src) {
  int destLen = strlen(dest);
  if (destLen >= destSize - 1) {
    return 0;
  }
  return strcopy(dest[destLen], destSize - destLen, src);
}

bool streq(const char[] left, const char[] right, bool ignoreCase = false) {
  return strcmp(left, right, !ignoreCase) == 0;
}

int ArrayBufSize(int len, int elemBufSize) {
  return 3 + len * (elemBufSize + 2);
}

int ToStr(char[] buf, int bufSize, const int[] arr, int len) {
  int written = append_str(buf, bufSize, "[");
  for (int i = 0; i < len; i++) {
    if (i != 0) {
      written += append_str(buf, bufSize, ", ");
    }
    char num[EBS_int];
    Format(num, sizeof(num), "%d", arr[i]);
    written += append_str(buf, bufSize, num);
  }
  written += append_str(buf, bufSize, "]");
  return written;
}

void ToLowercase(char[] s) {
  for (int i = 0; i < strlen(s); i++) {
    s[i] = CharToLower(s[i]);
  }
}

int IndexOf(const char[] string, const char[] pattern) {
  for (int index = 0, patLen = strlen(pattern), bound = strlen(string) - patLen; index < bound; index++) {
    bool match = true;
    for (int i = 0; i < patLen; i++) {
      if (string[index + i] != pattern[i]) {
        match = false;
        break;
      }
    }
    if (match) {
      return index;
    }
  }
  return -1;
}