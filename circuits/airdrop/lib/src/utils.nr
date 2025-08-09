use crate::constants::{
    MAX_CONTRIBUTIONS_JSON_LEN, MAX_OWNERSHIP_JSON_LEN, OWNERSHIP_JSON_LEN, PROXY_PUBKEY_X,
    PROXY_PUBKEY_Y,
};
use chacha20::ChaCha20;
use keccak256::keccak256;
use std::ecdsa_secp256k1::verify_signature;

pub struct JsonSlice<let MAX_JSON_LEN: u32> {
    json: str<MAX_JSON_LEN>,
    start: u32,
    end: u32,
}

fn verify_proxy_sig<let MAX_RECORD_LEN: u32>(
    encrypted_record: BoundedVec<u8, MAX_RECORD_LEN>,
    proxy_pubkey_x: [u8; 32],
    proxy_pubkey_y: [u8; 32],
    encrypted_record_signature: [u8; 64],
) {
    // DEV: Is using ciphertext.storage() safe?
    let encrypted_record_hash = keccak256(encrypted_record.storage(), encrypted_record.len());
    let is_verified = verify_signature(
        proxy_pubkey_x,
        proxy_pubkey_y,
        encrypted_record_signature,
        encrypted_record_hash,
    );
    assert(proxy_pubkey_x == PROXY_PUBKEY_X, "Unexpected proxy public key X!");
    assert(proxy_pubkey_y == PROXY_PUBKEY_Y, "Unexpected proxy public key Y!");
    assert(is_verified, "proxy did not sign encrypted_record_hash!");
}

fn encrypt_substring<let max_substring_len: u32>(
    mut key: [u32; 8],
    ctr: u32,
    mut nonce: [u32; 3],
    subtring: str<max_substring_len>,
    keystream_offset: u32,
) -> BoundedVec<u8, max_substring_len> {
    let substring_vec: BoundedVec<u8, max_substring_len> = str_to_bounded_vec(subtring);
    let chacha20 = ChaCha20::new(&mut key, ctr, &mut nonce);
    let encrypted_substring: BoundedVec<u8, max_substring_len> =
        chacha20.encrypt_with_offset(substring_vec, keystream_offset);

    encrypted_substring
}

fn check_encrypted_json_ownership<let MAX_RECORD_LEN: u32>(
    encrypted_record: BoundedVec<u8, MAX_RECORD_LEN>,
    encrypted_json: BoundedVec<u8, MAX_OWNERSHIP_JSON_LEN>,
    start: u32,
) {
    for i in 0..OWNERSHIP_JSON_LEN {
        assert(
            encrypted_record.get(i + start) == encrypted_json.get(i),
            "Encrypted JSON does not match expected value.",
        );
    }
}

fn check_encrypted_json_contributions<let MAX_RECORD_LEN: u32>(
    encrypted_record: BoundedVec<u8, MAX_RECORD_LEN>,
    encrypted_json: BoundedVec<u8, MAX_CONTRIBUTIONS_JSON_LEN>,
    start: u32,
    end: u32,
) {
    for i in 0..MAX_CONTRIBUTIONS_JSON_LEN {
        if (i + start) < end {
            assert(
                encrypted_record.get(i + start) == encrypted_json.get(i),
                "Encrypted JSON does not match expected value.",
            );
        }
    }
}

fn decrypt_record<let MAX_RECORD_LEN: u32>(
    mut key: [u32; 8],
    ctr: u32,
    mut nonce: [u32; 3],
    encrypted_record: BoundedVec<u8, MAX_RECORD_LEN>,
) -> BoundedVec<u8, MAX_RECORD_LEN> {
    let chacha20 = ChaCha20::new(&mut key, ctr, &mut nonce);
    let decrypted_record: BoundedVec<u8, MAX_RECORD_LEN> = chacha20.decrypt(encrypted_record);

    decrypted_record
}

fn encrypt_record<let max_record_len: u32>(
    mut key: [u32; 8],
    ctr: u32,
    mut nonce: [u32; 3],
    record: BoundedVec<u8, max_record_len>,
) -> BoundedVec<u8, max_record_len> {
    let encrypted_record: BoundedVec<u8, max_record_len> = decrypt_record(key, ctr, nonce, record);
    encrypted_record
}

fn get_proxy_pubkeys() -> ([u8; 32], [u8; 32]) {
    (PROXY_PUBKEY_X, PROXY_PUBKEY_Y)
}

fn str_to_bounded_vec<let MAX_LEN: u32>(s: str<MAX_LEN>) -> BoundedVec<u8, MAX_LEN> {
    let vec: BoundedVec<u8, MAX_LEN> = BoundedVec::from_array(s.as_bytes());

    vec
}

#[test]
fn test_check_encrypted_json_ownership() {
    // Full encrypted record sample
    let full_record: BoundedVec<u8, MAX_OWNERSHIP_JSON_LEN> = BoundedVec::from_array([
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]);

    // Sample sub-encrypted record
    let sub_record: BoundedVec<u8, MAX_OWNERSHIP_JSON_LEN> = BoundedVec::from_array([
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]);
    let start: u32 = 11; // Start index of the JSON in the encrypted response.
    check_encrypted_json_ownership(full_record, sub_record, start);
}
