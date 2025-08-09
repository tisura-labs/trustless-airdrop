use airdrop::constants::{
    MAX_OWNERSHIP_JSON_LEN, MAX_OWNERSHIP_RECORD_LEN, NODE_ID_LEN, OWNERSHIP_JSON_LEN,
};
use airdrop::utils::{
    check_encrypted_json_ownership, decrypt_record, encrypt_record, encrypt_substring,
    get_proxy_pubkeys, JsonSlice, str_to_bounded_vec, verify_proxy_sig,
};
use json_parser::{JSON, JSON512b};

pub struct SignaturePayload {
    pub encrypted_record: BoundedVec<u8, MAX_OWNERSHIP_RECORD_LEN>,
    pub encrypted_record_signed: [u8; 64],
    pub proxy_pubkey_x: [u8; 32],
    pub proxy_pubkey_y: [u8; 32],
}

pub struct AirdropPayload {
    pub node_id: str<NODE_ID_LEN>,
    pub graphql_response: JsonSlice<MAX_OWNERSHIP_JSON_LEN>,
}

impl SignaturePayload {
    pub fn verify_proxy_sig(self) {
        verify_proxy_sig(
            self.encrypted_record,
            self.proxy_pubkey_x,
            self.proxy_pubkey_y,
            self.encrypted_record_signed,
        );
    }
}

impl AirdropPayload {
    pub fn check_ownership(self) {
        check_ownership(self.graphql_response.json, self.node_id);
    }
}

fn main(
    mut key: [u32; 8],
    ctr: u32,
    mut nonce: [u32; 3],
    signature_payload: pub SignaturePayload,
    airdrop_payload: pub AirdropPayload,
) {
    // 1. Verify encrypted_record comes from the trusted proxy.
    signature_payload.verify_proxy_sig();

    // 2. Encrypt the substring of the GraphQL response on the specific keystream offset (start of the JSON in the full encrypted record).
    let encrypted_subtring: BoundedVec<u8, MAX_OWNERSHIP_JSON_LEN> = encrypt_substring(
        key,
        ctr,
        nonce,
        airdrop_payload.graphql_response.json,
        airdrop_payload.graphql_response.start,
    );

    // 3. Check whether the encrypted substring (JSON) is present in the full encrypted record.
    check_encrypted_json_ownership(
        signature_payload.encrypted_record,
        encrypted_subtring,
        airdrop_payload.graphql_response.start,
    );

    // 4. Check for the node id in the GraphQL response.
    airdrop_payload.check_ownership();
}

fn check_ownership(json_str: str<MAX_OWNERSHIP_JSON_LEN>, expected_node_id: str<NODE_ID_LEN>) {
    /*
    Expected JSON schema:
    {
        "viewer": {
            "id": "<node_id>"
        }
    }
    Where <node_id> is a 12 character string.
    */

    // Parse decrypted API response.
    let json: JSON512b = JSON::parse_json_from_string(json_str);
    let viewer: JSON512b = json.get_object_unchecked("viewer".as_bytes());
    let id: BoundedVec<u8, NODE_ID_LEN> = viewer.get_string_unchecked("id".as_bytes());

    // Assert `id` is the expected value.
    let expected_node_id_vec: BoundedVec<u8, NODE_ID_LEN> = str_to_bounded_vec(expected_node_id);
    assert(id == expected_node_id_vec);
}

#[test]
fn test_main() {
    let (mut key, ctr, mut nonce) = get_test_key_ctr_nonce();
    let plaintext: str<MAX_OWNERSHIP_JSON_LEN> =
        r#"xxxxxxxxxxxxxxxx{"viewer":{"id":"U_xxxxxxxxxx"}}xxxxxxxxxxxxxxxx"#;
    let node_id: str<NODE_ID_LEN> = "U_xxxxxxxxxx";

    // Calculate ciphertext.
    let mut plaintext_vec: BoundedVec<u8, MAX_OWNERSHIP_RECORD_LEN> = BoundedVec::new();
    plaintext_vec.extend_from_array(plaintext.as_bytes());
    let encrypted_record = encrypt_record(key, ctr, nonce, plaintext_vec);

    // DEV: we pad `json` with empty spaces because any other character will make JSON parsing [l. 55] fail.
    let json: str<MAX_OWNERSHIP_JSON_LEN> =
        r#"{"viewer":{"id":"U_xxxxxxxxxx"}}                                "#;
    let start: u32 = 16; // Start index of the JSON in the decrypted response.
    let end: u32 = OWNERSHIP_JSON_LEN + start; // End index of the JSON in the decrypted response.
    let json_slice = JsonSlice { json, start, end };

    let encrypted_record_signed: [u8; 64] = [
        92, 173, 161, 226, 195, 196, 53, 2, 197, 191, 168, 22, 251, 159, 216, 5, 42, 194, 52, 252,
        110, 42, 166, 8, 109, 44, 220, 202, 211, 216, 44, 76, 21, 57, 171, 183, 85, 250, 56, 254, 6,
        224, 114, 154, 81, 6, 113, 85, 39, 119, 172, 122, 124, 140, 53, 164, 40, 157, 243, 53, 73,
        86, 225, 79,
    ]; // Removed the last 0x01 which is the recovery id.
    let (proxy_pubkey_x, proxy_pubkey_y) = get_proxy_pubkeys();

    let signature_payload = SignaturePayload {
        encrypted_record,
        encrypted_record_signed,
        proxy_pubkey_x,
        proxy_pubkey_y,
    };

    let airdrop_payload = AirdropPayload { graphql_response: json_slice, node_id };

    main(key, ctr, nonce, signature_payload, airdrop_payload);
}

/*
    Test helpers.
*/

fn get_test_key_ctr_nonce() -> ([u32; 8], u32, [u32; 3]) {
    let key: [u32; 8] = [1, 2, 3, 4, 5, 6, 7, 8];
    let ctr: u32 = 1;
    let mut nonce: [u32; 3] = [1, 2, 3];
    (key, ctr, nonce)
}
