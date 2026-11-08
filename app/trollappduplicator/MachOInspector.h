#pragma once
#include <stdbool.h>

typedef struct {
    bool is_macho;
    bool malformed;
    bool encrypted;
    bool has_arm64;
    bool jailbreak_dependency;
    unsigned max_minimum_ios;
    unsigned slices;
} CloneMachOInfo;

CloneMachOInfo cloneInspectMachO(const char *path);
bool cloneMachOCodeEqual(const char *before, const char *after);
