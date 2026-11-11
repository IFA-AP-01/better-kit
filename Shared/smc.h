// Minimal AppleSMC client shared by the app (read-only) and the privileged helper (writes).
#ifndef BK_SMC_H
#define BK_SMC_H

#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint32_t key;
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t bytes[32];
} BKSMCValue;

/// Opens a connection to AppleSMC. Returns 0 on failure.
io_connect_t bk_smc_open(void);
void bk_smc_close(io_connect_t conn);

/// Four-character code helpers.
uint32_t bk_smc_fourcc(const char *key);
void bk_smc_fourcc_string(uint32_t code, char out[5]);

kern_return_t bk_smc_read(io_connect_t conn, uint32_t key, BKSMCValue *outValue);
kern_return_t bk_smc_write(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size);
kern_return_t bk_smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *outKey);
kern_return_t bk_smc_key_info(io_connect_t conn, uint32_t key, uint32_t *outSize, uint32_t *outType);

#endif
