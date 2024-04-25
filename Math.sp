#if defined _MATH_H
  #endinput
#endif
#define _MATH_H

float DistanceSquared(const float vecA[3], const float vecB[3]) {
  float dx = vecA[0] - vecB[0];
  float dy = vecA[1] - vecB[1];
  float dz = vecA[2] - vecB[2];

  return dx * dx + dy * dy + dz * dz;
}