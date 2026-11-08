#pragma once
#include <stdbool.h>
#include <stddef.h>

typedef struct CloneGroupPlan CloneGroupPlan;
// Thin arm64 only, exact group or group+OS cstrings, excluding crypt/code.
CloneGroupPlan *cloneGroupPlan(const char *path, const char *oldGroup);
size_t cloneGroupPatchCount(const CloneGroupPlan *plan);
bool cloneGroupApply(const char *path, const CloneGroupPlan *plan,
                     const char *oldGroup, const char *newGroup);
bool cloneGroupVerify(const char *before, const char *after, const CloneGroupPlan *plan,
                      const char *oldGroup, const char *newGroup);
void cloneGroupFree(CloneGroupPlan *plan);
