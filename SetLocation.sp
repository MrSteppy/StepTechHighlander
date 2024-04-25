#if defined _SET_LOCATION_H
  #endinput
#endif
#define _SET_LOCATION_H

#include <sourcemod>
#include <str_util.sp>

#define MAX_LOCATION_NAME_SIZE 16
#define MAX_LOCATIONS 20

SetLocation setLocations[MAX_LOCATIONS];

void AddSetLocation(int client, const char[] name, float location[3] = NULL_VECTOR) {
  if (IsNullVector(location)) {
    GetClientAbsOrigin(client, location);
  }

  static int id = 1;
  SetLocation setLocation;
  setLocation.id = id++;
  setLocation.client = client;
  setLocation.location = location;
  strcopy(setLocation.name, sizeof(setLocation.name), name);
  
  //find an index in the array which is either occupied with the same client and name, or the first one with the lowest id
  int index = 0;
  for (int i = 0; i < sizeof(setLocations); i++) {
    SetLocation slot;
    slot = setLocations[i];

    if (slot.client == client && streq(slot.name, name)) {
      index = i;
      break;
    }

    if (slot.id < setLocations[index].id) {
      index = i;
    }
  }

  setLocations[index] = setLocation;
}

bool GetSetLocation(SetLocation setLocation, int client, const char[] name) {
  for (int i = 0; i < sizeof(setLocations); i++) {
    SetLocation slot;
    slot = setLocations[i];

    if (slot.client == client && streq(slot.name, name)) {
      setLocation = slot;
      return true;
    }
  }
  return false;
}

enum struct SetLocation {
  float location[3];
  char name[MAX_LOCATION_NAME_SIZE];
  int client;
  int id;
}

