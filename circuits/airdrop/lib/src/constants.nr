global PROXY_PUBKEY_X: [u8; 32] = [
    221, 175, 66, 128, 34, 42, 173, 14, 103, 4, 220, 33, 90, 25, 201, 149, 17, 118, 33, 83, 28, 44,
    238, 247, 236, 72, 13, 255, 174, 240, 48, 198,
];
global PROXY_PUBKEY_Y: [u8; 32] = [
    212, 190, 236, 143, 82, 193, 27, 121, 215, 27, 140, 12, 209, 94, 229, 239, 135, 18, 195, 202,
    153, 109, 29, 237, 168, 183, 33, 143, 251, 136, 82, 213,
];

// IMPORTANT: The constants below that are used for encryption/decryption parameters must always
// be multiples of 64 (e.g., 1216 = 64 * 19).

// Ownership.
global MAX_OWNERSHIP_RECORD_LEN: u32 = 1216; // 64 * 19
global MAX_OWNERSHIP_JSON_LEN: u32 = 64; // Legnth of ownership JSON padded to 64
// TODO: Update OWNERSHIP_JSON_LEN to 41 when the circuit supports it.
global OWNERSHIP_JSON_LEN: u32 = 32; // Length of ownership JSON is always 41, but current version doesn't support full JSON consistently.
global NODE_ID_LEN: u32 = 12;

// Contributions.
global MAX_CONTRIBUTIONS_RECORD_LEN: u32 = 1280; // 64 * 20
global MAX_CONTRIBUTIONS_JSON_LEN: u32 = 192; // 64 * 3
global MAX_REPO_NAME_LEN: u32 = 20;
global MAX_REPO_OWNER_LEN: u32 = 20;
