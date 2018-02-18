#include <stdint.h>
#include <stdlib.h>
#include <linux/bpf_common.h>
#include <linux/filter.h>
#include <linux/bpf.h>
#include <asm/types.h>
#include "helper.h"

struct bpf_elf_map __section("maps") map_counter = {
  .type       = BPF_MAP_TYPE_ARRAY,
  .size_key   = sizeof(uint32_t),
  .size_value = sizeof(uint32_t),
  .max_elem   = 2,
};

__section("classifier") int cls_main(struct __sk_buff *skb)
{
    uint32_t key = 1;
    uint32_t init_val = 0;
    uint32_t *val;
    bpf_map_update_elem(&map_counter, &key, &init_val, BPF_NOEXIST);
    val = bpf_map_lookup_elem(&map_counter, &key);
	if (val) {
	    if (*val == 5) {
            *val = 0;
			return -1; //classifier match
		}
		else {
            *val = *val + 1;
            return 0; //missmatch
		}
	}
	else {
		return -1; //classifier match
	}
}

char __license[] __section("license") = "GPL";
