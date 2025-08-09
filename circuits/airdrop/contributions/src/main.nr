use airdrop::constants::{
    MAX_CONTRIBUTIONS_JSON_LEN, MAX_CONTRIBUTIONS_RECORD_LEN, MAX_REPO_NAME_LEN, MAX_REPO_OWNER_LEN,
};
use airdrop::utils::{
    check_encrypted_json_contributions, decrypt_record, encrypt_substring, get_proxy_pubkeys,
    JsonSlice, verify_proxy_sig,
};
use json_parser::{JSON, JSON512b};

pub struct SignaturePayload {
    pub encrypted_record: BoundedVec<u8, MAX_CONTRIBUTIONS_RECORD_LEN>,
    pub encrypted_record_signed: [u8; 64],
    pub proxy_pubkey_x: [u8; 32],
    pub proxy_pubkey_y: [u8; 32],
}

pub struct AirdropPayload {
    pub repo_name: BoundedVec<u8, MAX_REPO_NAME_LEN>,
    pub repo_owner: BoundedVec<u8, MAX_REPO_OWNER_LEN>,
    pub n_contributions: u64,
    pub graphql_response: JsonSlice<MAX_CONTRIBUTIONS_JSON_LEN>,
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
    pub fn check_contributions(self) {
        check_contributions(
            self.graphql_response.json,
            self.repo_name,
            self.repo_owner,
            self.n_contributions,
        );
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
    let encrypted_subtring: BoundedVec<u8, MAX_CONTRIBUTIONS_JSON_LEN> = encrypt_substring(
        key,
        ctr,
        nonce,
        airdrop_payload.graphql_response.json,
        airdrop_payload.graphql_response.start,
    );

    // 3. Check whether the encrypted substring (JSON) is present in the full encrypted record.
    check_encrypted_json_contributions(
        signature_payload.encrypted_record,
        encrypted_subtring,
        airdrop_payload.graphql_response.start,
        airdrop_payload.graphql_response.end,
    );

    // 4. Check for the number of contributions in the GraphQL response.
    airdrop_payload.check_contributions();
}

fn check_contributions(
    json_str: str<MAX_CONTRIBUTIONS_JSON_LEN>,
    expected_repo_name: BoundedVec<u8, MAX_REPO_NAME_LEN>,
    expected_repo_owner: BoundedVec<u8, MAX_REPO_OWNER_LEN>,
    n_contributions: u64,
) {
    /*
    Expected JSON schema:
    {
        "repository":{
            "name":<repository_name>,
            "owner":{
                "login":<repository_owner>,
            },
            "defaultBranchRef":{
                "target":{
                    "history":{
                        "totalCount":<n>
                    }
                }
            }
        }
    }

    Where <n> is the number commits in the repo's default branch.
    */

    let json: JSON512b = JSON::parse_json_from_string(json_str);
    let repo: JSON512b = json.get_object_unchecked("repository".as_bytes());

    // Parse decrypted API response to get `repo_name` and `repo_owner`.
    let repo_name: BoundedVec<u8, MAX_REPO_NAME_LEN> = repo.get_string_unchecked("name".as_bytes());
    let owner: JSON512b = repo.get_object_unchecked("owner".as_bytes());
    let repo_owner: BoundedVec<u8, MAX_REPO_OWNER_LEN> =
        owner.get_string_unchecked("login".as_bytes());

    // Assert we're on the correct repo, identified by the name and owner.
    assert(repo_name == expected_repo_name, "Unexpected repo name!");
    assert(repo_owner == expected_repo_owner, "Unexpected repo owner!");

    // Parse decrypted API response to get `n_contributions`.
    let default_branch_ref: JSON512b = repo.get_object_unchecked("defaultBranchRef".as_bytes());
    let target: JSON512b = default_branch_ref.get_object_unchecked("target".as_bytes());
    let history: JSON512b = target.get_object_unchecked("history".as_bytes());
    let total_count: u64 = history.get_number_unchecked("totalCount".as_bytes());

    // Assert `totalCount` is the expected value.
    assert(total_count == n_contributions, "Unexpected number of contributions!");
}

#[test]
fn test_main() {
    let (mut key, ctr, mut nonce) = get_test_key_ctr_nonce();
    let plaintext: str<128> = r#"xxxx{"repository":{"name":"mono","owner":{"login":"tisura-labs"},"defaultBranchRef":{"target":{"history":{"totalCount":50}}}}}xx"#;
    let (repo_name, repo_owner, n_contributions) = get_test_repo_name_owner_n_contributions();

    // Calculate ciphertext.
    let mut plaintext_vec: BoundedVec<u8, MAX_CONTRIBUTIONS_RECORD_LEN> = BoundedVec::new();
    plaintext_vec.extend_from_array(plaintext.as_bytes());
    let encrypted_record = decrypt_record(key, ctr, nonce, plaintext_vec); // decrypt_record encrypts plaintext.
    let encrypted_record_signed: [u8; 64] = get_test_encrypted_record_signed();
    let (proxy_pubkey_x, proxy_pubkey_y) = get_proxy_pubkeys();

    // DEV: we pad `json` with empty spaces because any other character will make JSON parsing [l. 84] fail.
    let json: str<MAX_CONTRIBUTIONS_JSON_LEN> = r#"{"repository":{"name":"mono","owner":{"login":"tisura-labs"},"defaultBranchRef":{"target":{"history":{"totalCount":50}}}}}                                                                      "#;
    let start: u32 = 4; // Start index of the JSON in the decrypted response.
    let end: u32 = 126; // End index of the JSON in the decrypted response. 126 = 4 + 122 (length of the JSON).
    let json_slice = JsonSlice { json, start, end };

    let signature_payload = SignaturePayload {
        encrypted_record,
        encrypted_record_signed,
        proxy_pubkey_x,
        proxy_pubkey_y,
    };

    let airdrop_payload =
        AirdropPayload { graphql_response: json_slice, repo_name, repo_owner, n_contributions };

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

fn get_test_repo_name_owner_n_contributions() -> (BoundedVec<u8, MAX_REPO_NAME_LEN>, BoundedVec<u8, MAX_REPO_OWNER_LEN>, u64) {
    let repo_name = "mono".as_bytes();
    let repo_name_vec: BoundedVec<u8, MAX_REPO_NAME_LEN> = BoundedVec::from_array(repo_name);

    let repo_owner = "tisura-labs".as_bytes();
    let repo_owner_vec: BoundedVec<u8, MAX_REPO_OWNER_LEN> = BoundedVec::from_array(repo_owner);

    let n_contributions: u64 = 50;

    (repo_name_vec, repo_owner_vec, n_contributions)
}

fn get_test_encrypted_record_signed() -> [u8; 64] {
    [
        70, 21, 71, 31, 172, 86, 7, 169, 199, 154, 245, 163, 14, 51, 250, 28, 160, 83, 33, 61, 41,
        81, 120, 50, 229, 239, 28, 247, 134, 111, 161, 10, 72, 253, 149, 27, 189, 81, 234, 23, 72,
        78, 203, 189, 228, 91, 239, 225, 212, 236, 11, 91, 120, 57, 188, 92, 1, 41, 4, 192, 252,
        202, 87, 83,
    ] // Removed the last byte which is the recovery id.
}
