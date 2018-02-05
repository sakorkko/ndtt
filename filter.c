#include <stdint.h>
#include <stdlib.h>
#include <linux/bpf_common.h>
#include <linux/filter.h>
#include <linux/bpf.h>
#include <asm/types.h>

// Some used BPF function calls.
static void *(*bpf_map_lookup_elem)(void *map, void *key) = (void *) BPF_FUNC_map_lookup_elem;
static int (*bpf_map_update_elem)(void *map, void *key, void *value, int flags) = (void *) BPF_FUNC_map_update_elem;

// Tc autoloads ELF sections maps, classifier, action
#ifndef __section
# define __section(x)  __attribute__((section(x), used))
#endif

struct bpf_elf_map {
	__u32 type;        // Map type: Array, hash, etc.
	__u32 size_key;    // Size of key in bytes
	__u32 size_value;  // Size of value in bytes
	__u32 max_elem;    // Max entries in a map
};

struct bpf_elf_map __section("maps") map_counter = {
    .type       = BPF_MAP_TYPE_ARRAY,
    .size_key   = sizeof(uint32_t),
    .size_value = sizeof(uint32_t),
    .max_elem   = 1,
};

// void *bpf_map_lookup_elem(&map, &key)
//     Return: Map value or NULL
// int bpf_map_update_elem(&map, &key, &value, flags)
//     Return: 0 on success or negative error

__section("classifier") int cls_main(struct __sk_buff *skb)
{
    struct bpf_elf_map *map_counter;
    int key = 0, *val;
    val = bpf_map_lookup_elem(&map_counter, &key);

    // Count 0-2 for every incoming package, match filter on 2
    if (val) {
        if (*val == 2) {
            bpf_map_update_elem(&map_counter, &key, 0, BPF_ANY);
            return -1; //classifier match
        }
        else {
            *val = *val + 1;
            bpf_map_update_elem(&map_counter, &key, val, BPF_ANY);
            return 0; //classifier missmatch
        }
    }
    else {
        bpf_map_update_elem(&map_counter, &key, 0, BPF_ANY);
        return 0; //classifier missmatch
    }
}

char __license[] __section("license") = "GPL";
