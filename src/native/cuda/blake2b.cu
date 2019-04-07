#include "kernels.h"


#define IV0 0x6a09e667f3bcc908UL
#define IV1 0xbb67ae8584caa73bUL
#define IV2 0x3c6ef372fe94f82bUL
#define IV3 0xa54ff53a5f1d36f1UL
#define IV4 0x510e527fade682d1UL
#define IV5 0x9b05688c2b3e6c1fUL
#define IV6 0x1f83d9abfb41bd6bUL
#define IV7 0x5be0cd19137e2179UL

__constant__ static const uint8_t sigma[12][16] = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
    {11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
    {7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
    {9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
    {2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
    {12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
    {13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
    {6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
    {10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
    {14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
};

__device__ __forceinline__ uint64_t rotr64(uint64_t x, uint32_t n)
{
    return (x >> n) | (x << (64 - n));
}

__device__ __forceinline__ uint32_t swap32(uint32_t x)
{
    return ((x & 0x000000FF) << 24)
        | ((x & 0x0000FF00) << 8)
        | ((x & 0x00FF0000) >> 8)
        | ((x & 0xFF000000) >> 24);
}

__device__ __forceinline__ uint64_t swap64(uint64_t x)
{
    return ((x & 0x00000000000000FFUL) << 56)
        | ((x & 0x000000000000FF00UL) << 40)
        | ((x & 0x0000000000FF0000UL) << 24)
        | ((x & 0x00000000FF000000UL) <<  8)
        | ((x & 0x000000FF00000000UL) >>  8)
        | ((x & 0x0000FF0000000000UL) >> 24)
        | ((x & 0x00FF000000000000UL) >> 40)
        | ((x & 0xFF00000000000000UL) >> 56);
}

__device__ void blake2b_init(uint64_t *h, uint32_t hashlen)
{
    h[0] = IV0 ^ (0x01010000 | hashlen);
    h[1] = IV1;
    h[2] = IV2;
    h[3] = IV3;
    h[4] = IV4;
    h[5] = IV5;
    h[6] = IV6;
    h[7] = IV7;
}

#define G(i, a, b, c, d)                    \
    do {                                    \
        a = a + b + m[sigma[r][2 * i]];     \
        d = rotr64(d ^ a, 32);              \
        c = c + d;                          \
        b = rotr64(b ^ c, 24);              \
        a = a + b + m[sigma[r][2 * i + 1]]; \
        d = rotr64(d ^ a, 16);              \
        c = c + d;                          \
        b = rotr64(b ^ c, 63);              \
    } while(0)

#define ROUND()                          \
    do {                                 \
        G(0, v[0], v[4], v[8], v[12]);   \
        G(1, v[1], v[5], v[9], v[13]);   \
        G(2, v[2], v[6], v[10], v[14]);  \
        G(3, v[3], v[7], v[11], v[15]);  \
        G(4, v[0], v[5], v[10], v[15]);  \
        G(5, v[1], v[6], v[11], v[12]);  \
        G(6, v[2], v[7], v[8], v[13]);   \
        G(7, v[3], v[4], v[9], v[14]);   \
    } while(0)

__device__ void blake2b_compress(uint64_t *h, uint64_t *m, uint32_t bytes_compressed, bool last_block)
{
    uint64_t v[BLAKE2B_QWORDS_IN_BLOCK];

    v[0] = h[0];
    v[1] = h[1];
    v[2] = h[2];
    v[3] = h[3];
    v[4] = h[4];
    v[5] = h[5];
    v[6] = h[6];
    v[7] = h[7];
    v[8] = IV0;
    v[9] = IV1;
    v[10] = IV2;
    v[11] = IV3;
    v[12] = IV4 ^ bytes_compressed;
    v[13] = IV5; // it's OK if below 2^32 bytes
    v[14] = last_block ? ~IV6 : IV6;
    v[15] = IV7;

    #pragma unroll
    for (uint32_t r = 0; r < 12; r++)
    {
      ROUND();
    }

    h[0] = h[0] ^ v[0] ^ v[8];
    h[1] = h[1] ^ v[1] ^ v[9];
    h[2] = h[2] ^ v[2] ^ v[10];
    h[3] = h[3] ^ v[3] ^ v[11];
    h[4] = h[4] ^ v[4] ^ v[12];
    h[5] = h[5] ^ v[5] ^ v[13];
    h[6] = h[6] ^ v[6] ^ v[14];
    h[7] = h[7] ^ v[7] ^ v[15];
}

__device__ __forceinline__ void set_nonce(uint64_t *inseed, uint32_t nonce)
{
    // bytes 170-173
    uint64_t n = swap32(nonce);
    inseed[21] = (inseed[21] & 0xFFFF00000000FFFFUL) | (n << 16);
}

__device__ void initial_hash(uint64_t *hash, uint64_t *inseed, uint32_t nonce)
{
    uint64_t is[32];
    memcpy(is, inseed, sizeof(is));
    set_nonce(is, nonce);

    blake2b_init(hash, BLAKE2B_HASH_LENGTH);
    blake2b_compress(hash, &is[0], BLAKE2B_BLOCK_SIZE, false);
    blake2b_compress(hash, &is[BLAKE2B_QWORDS_IN_BLOCK], ARGON2_INITIAL_SEED_SIZE, true);
}

__device__ void fill_first_block(struct block_g *memory, uint64_t *inseed, uint32_t nonce, uint32_t block)
{
    uint64_t hash[8];
    initial_hash(hash, inseed, nonce);

    uint32_t prehash_seed[32] = {ARGON2_BLOCK_SIZE};
    #pragma unroll
    for (uint32_t i = 0; i < 8; i++)
    {
        prehash_seed[2 * i + 1] = (uint) hash[i];
        prehash_seed[2 * i + 2] = (uint) (hash[i] >> 32);
    }
    prehash_seed[17] = block;

    uint64_t buffer[BLAKE2B_QWORDS_IN_BLOCK] = {0};
    uint64_t *dst = memory->data;

    // V1
    blake2b_init(hash, BLAKE2B_HASH_LENGTH);
    blake2b_compress(hash, (uint64_t *) prehash_seed, ARGON2_PREHASH_SEED_SIZE, true);

    *(dst++) = hash[0];
    *(dst++) = hash[1];
    *(dst++) = hash[2];
    *(dst++) = hash[3];

    // V2-Vr
    for (int r = 2; r < 2 * ARGON2_BLOCK_SIZE / BLAKE2B_HASH_LENGTH; r++)
    {
        buffer[0] = hash[0];
        buffer[1] = hash[1];
        buffer[2] = hash[2];
        buffer[3] = hash[3];
        buffer[4] = hash[4];
        buffer[5] = hash[5];
        buffer[6] = hash[6];
        buffer[7] = hash[7];

        blake2b_init(hash, BLAKE2B_HASH_LENGTH);
        blake2b_compress(hash, buffer, BLAKE2B_HASH_LENGTH, true);

        *(dst++) = hash[0];
        *(dst++) = hash[1];
        *(dst++) = hash[2];
        *(dst++) = hash[3];
    }

    *(dst++) = hash[4];
    *(dst++) = hash[5];
    *(dst++) = hash[6];
    *(dst++) = hash[7];
}

__device__ void compact_to_target(uint32_t share_compact, uint64_t *target)
{
    uint32_t offset = (share_compact >> 24) - 3; // offset in bytes
    uint64_t value = share_compact & 0xFFFFFF;
    uint64_t hi = value >> ((8 - offset & 0x7) << 3);
    uint64_t lo = value << ((offset & 0x7) << 3); // value << (8 * (offset % 8))

    target[0] = (offset >= 24) ? lo : (offset > 20) ? hi : 0;
    target[1] = (offset >= 24) ? 0 : (offset >= 16) ? lo : (offset > 12) ? hi : 0;
    target[2] = (offset >= 16) ? 0 : (offset >= 8) ? lo : (offset > 4) ? hi : 0;
    target[3] = (offset < 8) ? lo : 0;
}

__device__ bool is_proof_of_work(uint64_t *hash, uint64_t *target)
{
    #pragma unroll
    for (uint32_t i = 0; i < 4; i++)
    {
        if (swap64(hash[i]) < target[i]) return true;
        if (swap64(hash[i]) > target[i]) return false;
    }
    return true;
}

__device__ void hash_last_block(struct block_g *memory, uint64_t *hash)
{
    uint64_t buffer[BLAKE2B_QWORDS_IN_BLOCK];
    uint32_t hi, lo;
    uint32_t bytes_compressed = 0;
    uint32_t bytes_remaining = ARGON2_BLOCK_SIZE;
    uint32_t *src = (uint32_t *)memory->data;

    blake2b_init(hash, ARGON2_HASH_LENGTH);

    hi = *(src++);
    buffer[0] = ARGON2_HASH_LENGTH | ((uint64_t)hi << 32);

    #pragma unroll
    for (uint32_t i = 1; i < BLAKE2B_QWORDS_IN_BLOCK; i++)
    {
        lo = *(src++);
        hi = *(src++);
        buffer[i] = lo | ((uint64_t)hi << 32);
    }

    bytes_compressed += BLAKE2B_BLOCK_SIZE;
    bytes_remaining -= (BLAKE2B_BLOCK_SIZE - sizeof(uint32_t));
    blake2b_compress(hash, buffer, bytes_compressed, false);

    while (bytes_remaining > BLAKE2B_BLOCK_SIZE)
    {
        #pragma unroll
        for (uint32_t i = 0; i < BLAKE2B_QWORDS_IN_BLOCK; i++)
        {
            lo = *(src++);
            hi = *(src++);
            buffer[i] = lo | ((uint64_t)hi << 32);
        }
        bytes_compressed += BLAKE2B_BLOCK_SIZE;
        bytes_remaining -= BLAKE2B_BLOCK_SIZE;
        blake2b_compress(hash, buffer, bytes_compressed, false);
    }

    buffer[0] = *src;
    #pragma unroll
    for (uint32_t i = 1; i < BLAKE2B_QWORDS_IN_BLOCK; i++)
    {
        buffer[i] = 0;
    }
    bytes_compressed += bytes_remaining;
    blake2b_compress(hash, buffer, bytes_compressed, true);
}

__global__ void init_memory(struct block_g *memory, uint64_t *inseed, uint32_t start_nonce)
{
    uint32_t job_id = blockIdx.x * blockDim.x + threadIdx.x;
    uint32_t nonce = start_nonce + job_id;
    uint32_t block = threadIdx.y;

    memory += (size_t)job_id * MEMORY_COST + block;
    fill_first_block(memory, inseed, nonce, block);
}

__global__ void get_nonce(struct block_g *memory, uint32_t start_nonce, uint32_t share_compact, uint32_t *nonce)
{
    uint32_t job_id = blockIdx.x * blockDim.x + threadIdx.x;
    memory += (size_t)(job_id + 1) * MEMORY_COST - 1;

    uint64_t hash[8];
    uint64_t target[4];

    compact_to_target(share_compact, target);
    hash_last_block(memory, hash);

    if (is_proof_of_work(hash, target))
    {
        atomicCAS(nonce, 0, start_nonce + job_id);
    }
}
