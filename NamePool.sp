#if defined _NAME_POOL_H
  #endinput
#endif
#define _NAME_POOL_H

#include <str_util.sp>

#define NP_NAME_SIZE 32 //how many bytes are allocated for a name
#define NP_MAX_NAME_SET_SIZE 4 //how many names a name set can hold
#define NP_MAX_CLASS_NAME_SETS 8 //how many name sets there can be in a name class
#define NP_NUM_CLASSES 10 //the number of name classes

#define NP_NAME_SET_SIZE    NP_MAX_NAME_SET_SIZE * NP_NAME_SIZE
#define NP_NAME_CLASS_SIZE  NP_MAX_CLASS_NAME_SETS * NP_NAME_SET_SIZE
#define NP_HEAP_SIZE        NP_NUM_CLASSES * NP_NAME_CLASS_SIZE

enum struct NamePool {
  char heap[NP_HEAP_SIZE];
  int numSets[NP_NUM_CLASSES]; //how many name sets each class has

  bool GetRandomNameSet(int nameClass, NameSet buf, int defNameClass = -1) {
    this._CheckIndex(nameClass);

    buf.size = 0;
    int available = this.numSets[nameClass];

    if (available > 0) {
      int nameSetIndex = GetRandomInt(0, available - 1); //both indices inclusive
      int nameSetAddr = nameClass * NP_NAME_CLASS_SIZE + nameSetIndex * NP_NAME_SET_SIZE;
      
      for (int i = 0; i < NP_MAX_NAME_SET_SIZE; i++) {
        int nameAddr = nameSetAddr + i * NP_NAME_SIZE;
        if (strlen(this.heap[nameAddr]) > 0) {
          buf.Add(this.heap[nameAddr]);
        } else {
          break;
        }
      }

      if (buf.size > 0) {
        return true; //we found a nameset in the desired class
      }
    }

    if (defNameClass > -1) {
      this.GetRandomNameSet(defNameClass, buf);
    }

    return false; //we didn't find a nameset in the desired class
  }

  bool AddNameSet(int nameClass, NameSet nameSet) {
    this._CheckIndex(nameClass);

    int nameSetIndex = this.numSets[nameClass];
    if (nameSetIndex >= NP_MAX_CLASS_NAME_SETS) {
      return false; //out of memory
    }

    if (nameSet.size <= 0) {
      return true;
    }

    int nameSetAddr = nameClass * NP_NAME_CLASS_SIZE + nameSetIndex * NP_NAME_SET_SIZE;
    for (int i = 0; i < nameSet.size; i++) {
      nameSet.Get(i, this.heap[nameSetAddr + i * NP_NAME_SIZE], NP_NAME_SIZE);
    }
    this.numSets[nameClass]++;

    return true;
  }

  void _CheckIndex(int nameClass) {
    if (nameClass < 0 || nameClass >= NP_NUM_CLASSES) {
      ThrowError("index %d out of bounds for size %d", nameClass, NP_NUM_CLASSES);
    }
  }
}

enum struct NameSet {
  char names[NP_NAME_SIZE * NP_MAX_NAME_SET_SIZE];
  int size;

  int GetOrDefault(int index, char[] buf, int bufLen, const char[] def) {
    return this.Get(index, buf, bufLen, def, true);
  }

  int Get(int index, char[] buf, int bufLen, const char[] def = "", bool defPresent = false) {
    if (strlen(def) > 0) defPresent = true;

    bool indexOob = index >= this.size;
    if (indexOob && defPresent) {
      return strcopy(buf, bufLen, def);
    }
    if (index < 0 || indexOob) {
      ThrowError("index %d out of bounds for size %d", index, this.size);
    }
    return strcopy(buf, bufLen, this.names[index * NP_NAME_SIZE]);
  }

  int Add(const char[] name) {
    if (this.size >= NP_MAX_NAME_SET_SIZE) {
      return -1; //out of memory
    }

    return strcopy(this.names[this.size++ * NP_NAME_SIZE], NP_NAME_SIZE, name);
  }

  int GetRequiredStrBufSize() {
    return 2 + this.size * (NP_NAME_SIZE + 2) + 1;
  }

  int ToString(char[] buf, int bufSize = -1) {
    if (bufSize == -1) {
      bufSize = this.GetRequiredStrBufSize();
    }
    int written = 0;
    written += append_str(buf, bufSize, "[");
    for (int i = 0; i < this.size; i++) {
      if (i != 0) {
        written += append_str(buf, bufSize, ", ")
      }
      char name[NP_NAME_SIZE];
      this.Get(i, name, sizeof(name));
      written += append_str(buf, bufSize, name);
    }
    written += append_str(buf, bufSize, "]");
    return written;
  }
}
