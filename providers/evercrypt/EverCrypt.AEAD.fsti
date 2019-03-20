module EverCrypt.AEAD

/// The new AEAD interface for EverCrypt, which supersedes the functions found
/// in EverCrypt.fst
///
/// The expected usage for this module is as follows:
/// - client expands key, obtaining an ``expanded_key a``
/// - client uses ``encrypt``/``decrypt`` with the same ``expanded_key a`` repeatedly.
///
/// This usage protocol is enforced for verified F* clients but, naturally,
/// isn't for C clients.

module S = FStar.Seq
module G = FStar.Ghost

module HS = FStar.HyperStack
module ST = FStar.HyperStack.ST
module MB = LowStar.Monotonic.Buffer
module B = LowStar.Buffer

open FStar.HyperStack.ST
open FStar.Integers

open Spec.AEAD

/// Note: if the fst and the fsti are running on different fuel settings,
/// something that works in the interactive mode for the fsti, when
/// "re-interpreted" in the fst, might stop working!
#set-options "--max_fuel 0 --max_ifuel 0"

noextract
let bytes = Seq.seq UInt8.t

let frozen_preorder (s: bytes): MB.srel UInt8.t = fun (s1 s2: bytes) ->
  S.equal s1 s ==> S.equal s2 s

/// We need to be able to return a proper ``expanded_key`` even if the algorithm
/// is unsupported, so that C clients don't trip this interface. Alternatively,
/// we could remove this layer of complexity and let C clients get a fatal
/// kremlin abort if they try to use AEAD for an unsupported algorithm (see
/// 486790f5).
let kv_or_dummy (a: alg) = if is_supported_alg a then kv a else bytes

let expand_or_dummy (a: alg) (kv: G.erased (kv_or_dummy a)) =
  if is_supported_alg a then
    // JP: I regularly have to perform let-bindings for these refinement types to work
    let a = a in
    expand #a (G.reveal kv)
  else
    S.empty

/// This type, following several rounds of optimization by KreMLin, will extract
/// to a regular pointer type. A NULL pointer indicates an invalid expanded key.
noeq
type expanded_key (a: alg) =
| EK:
    kv:G.erased (kv_or_dummy a) ->
    ek:(
    [@ inline_let ]
    let s = expand_or_dummy a kv in
    [@ inline_let ]
    let p = frozen_preorder s in
    ek:MB.mbuffer UInt8.t p p { not (MB.g_is_null ek) ==> MB.witnessed ek (S.equal s) }) ->
    expanded_key a

/// When successful, this function returns a non-NULL pointer that has been
/// freshly allocated and that contains the expanded key.
///
/// Possible causes for a NULL pointer include:
/// - unsupported algorithm
/// - unavailable implementation on target platform
val expand_in:
  #a:alg ->
  r:HS.rid ->
  k:B.buffer UInt8.t { B.length k = key_length a } ->
  ST (expanded_key a)
    (requires fun h0 ->
      ST.is_eternal_region r /\
      B.live h0 k)
    (ensures fun h0 ek h1 ->
      let l = B.loc_buffer (EK?.ek ek) in
      Hash.fresh_loc l h0 h1 /\
      B.(modifies loc_none h0 h1) /\
      B.(loc_includes (loc_region_only true r) l) /\
      (not (MB.g_is_null (EK?.ek ek)) ==> (
        S.equal (G.reveal (EK?.kv ek)) (B.as_seq h0 k) /\
        is_supported_alg a)))

let iv_p a = iv:B.buffer UInt8.t { B.length iv = iv_length a }
let ad_p a = ad:B.buffer UInt8.t { B.length ad <= max_length a }
let plain_p a = p:B.buffer UInt8.t { B.length p <= max_length a }

type error_code =
| Success
| InvalidKey
| Failure

let _: squash (inversion error_code) = allow_inversion error_code

/// This function takes a previously expanded key and performs encryption.
///
/// Possible return values are:
/// - ``Success``: encryption was successfully performed
/// - ``InvalidKey``: the function was passed a NULL expanded key (see above)
/// ``Failure`` is currently unused but may be used in the future.
val encrypt:
  #a:supported_alg ->
  ek:expanded_key a ->
  iv:iv_p a ->
  ad:ad_p a ->
  ad_len: UInt32.t { v ad_len = B.length ad /\ v ad_len <= pow2 31 } ->
  plain: plain_p a ->
  plain_len: UInt32.t { v plain_len = B.length plain /\ v plain_len <= max_length a } ->
  dst: B.buffer UInt8.t { B.length dst = B.length plain + tag_length a } ->
  Stack error_code
    (requires fun h0 ->
      MB.(all_live h0 [ buf (EK?.ek ek); buf iv; buf ad; buf plain; buf dst ]) /\
      (B.disjoint plain dst \/ plain == dst) /\
      B.disjoint iv dst /\
      B.disjoint ad dst)
    (ensures fun h0 r h1 ->
      match r with
      | Success ->
          B.(modifies (loc_buffer dst) h0 h1) /\
          S.equal (B.as_seq h1 dst)
            (encrypt #a (G.reveal (EK?.kv ek)) (B.as_seq h0 iv) (B.as_seq h0 ad) (B.as_seq h0 plain))
      | InvalidKey ->
          B.(modifies loc_none h0 h1)
      | Failure ->
        False)

/// This function takes a previously expanded key and performs decryption.
///
/// Possible return values are:
/// - ``Success``: decryption was successfully performed
/// - ``InvalidKey``: the function was passed a NULL expanded key (see above)
/// - ``Failure``: cipher text could not be decrypted (e.g. tag mismatch)
val decrypt:
  #a:supported_alg ->
  ek:expanded_key a ->
  iv:iv_p a ->
  ad:ad_p a ->
  ad_len: UInt32.t { v ad_len = B.length ad } ->
  cipher: plain_p a ->
  cipher_len: UInt32.t { v cipher_len = B.length cipher } ->
  dst: B.buffer UInt8.t { B.length dst = B.length cipher - tag_length a } ->
  Stack error_code
    (requires fun h0 ->
      B.live h0 (EK?.ek ek) /\
      B.live h0 iv /\
      B.live h0 ad /\
      B.live h0 cipher /\
      B.live h0 dst)
    (ensures fun h0 err h1 ->
      let kv = G.reveal (EK?.kv ek) in
      let plain = decrypt #a kv (B.as_seq h0 iv) (B.as_seq h0 ad) (B.as_seq h0 cipher) in
      match err with
      | InvalidKey ->
          B.(modifies loc_none h0 h1)
      | Success ->
          B.(modifies (loc_buffer dst) h0 h1) /\
          Some? plain /\ S.equal (Some?.v plain) (B.as_seq h1 dst)
      | Failure ->
          B.(modifies (loc_buffer dst) h0 h1) /\
          None? plain)
