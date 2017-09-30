module Hacl.Hash.SHA2_256

open FStar.HyperStack.All

module ST = FStar.HyperStack.ST

open FStar.Mul
open FStar.Ghost
open FStar.HyperStack
open FStar.HyperStack.ST
open FStar.Buffer

open C.Loops

open Hacl.Spec.Endianness
open Hacl.Cast
open Hacl.UInt8
open Hacl.UInt32
open FStar.UInt32

open Hacl.Hash.Lib.Create
open Hacl.Hash.Lib.LoadStore


(* Definition of aliases for modules *)
module U8 = FStar.UInt8
module U32 = FStar.UInt32
module U64 = FStar.UInt64

module H32 = Hacl.UInt32
module H64 = Hacl.UInt64

module HS = FStar.HyperStack
module Cast = Hacl.Cast

module Spec = Spec.SHA2_256
module Lemmas = Hacl.Hash.SHA2_256.Lemmas


(* Definition of base types *)
private let uint8_t   = FStar.UInt8.t
private let uint32_t  = FStar.UInt32.t
private let uint64_t  = FStar.UInt64.t

private let uint8_ht  = Hacl.UInt8.t
private let uint32_ht = Hacl.UInt32.t
private let uint64_ht = Hacl.UInt64.t

private let uint32_p = Buffer.buffer uint32_ht
private let uint8_p  = Buffer.buffer uint8_ht


(* Definitions of aliases for functions *)
inline_for_extraction let u8_to_h8 = Cast.uint8_to_sint8
inline_for_extraction let u32_to_h32 = Cast.uint32_to_sint32
inline_for_extraction let u32_to_h64 = Cast.uint32_to_sint64
inline_for_extraction let h32_to_h8  = Cast.sint32_to_sint8
inline_for_extraction let h32_to_h64 = Cast.sint32_to_sint64
inline_for_extraction let u64_to_h64 = Cast.uint64_to_sint64


#reset-options "--max_fuel 0  --z3rlimit 10"

//
// SHA-256
//

(* Define word size *)
inline_for_extraction let size_word = 4ul // Size of the word in bytes

(* Define algorithm parameters *)
inline_for_extraction let size_hash_w   = 8ul // 8 words (Final hash output size)
inline_for_extraction let size_block_w  = 16ul  // 16 words (Working data block size)
inline_for_extraction let size_hash     = size_word *^ size_hash_w
inline_for_extraction let size_block    = size_word *^ size_block_w
inline_for_extraction let max_input_len = 2305843009213693952uL // 2^61 Bytes

(* Sizes of objects in the state *)
inline_for_extraction let size_k_w     = 64ul  // 2048 bits = 64 words of 32 bits (size_block)
inline_for_extraction let size_ws_w    = size_k_w
inline_for_extraction let size_whash_w = size_hash_w
inline_for_extraction let size_count_w = 1ul  // 1 word
inline_for_extraction let size_len_8   = 2ul *^ size_word


(* Positions of objects in the state *)
inline_for_extraction let pos_k_w      = 0ul
inline_for_extraction let pos_ws_w     = size_k_w
inline_for_extraction let pos_whash_w  = size_k_w +^ size_ws_w
inline_for_extraction let pos_count_w  = size_k_w +^ size_ws_w +^ size_whash_w


[@"substitute"]
let rotate_right (a:uint32_ht) (b:uint32_t{0 < v b && v b < 32}) : Tot uint32_ht =
  H32.logor (H32.shift_right a b) (H32.shift_left a (U32.sub 32ul b))

[@"substitute"]
private val _Ch: x:uint32_ht -> y:uint32_ht -> z:uint32_ht -> Tot uint32_ht
[@"substitute"]
let _Ch x y z = H32.logxor (H32.logand x y) (H32.logand (H32.lognot x) z)

[@"substitute"]
private val _Maj: x:uint32_ht -> y:uint32_ht -> z:uint32_ht -> Tot uint32_ht
[@"substitute"]
let _Maj x y z = H32.logxor (H32.logand x y) (H32.logxor (H32.logand x z) (H32.logand y z))

[@"substitute"]
private val _Sigma0: x:uint32_ht -> Tot uint32_ht
[@"substitute"]
let _Sigma0 x = H32.logxor (rotate_right x 2ul) (H32.logxor (rotate_right x 13ul) (rotate_right x 22ul))

[@"substitute"]
private val _Sigma1: x:uint32_ht -> Tot uint32_ht
[@"substitute"]
let _Sigma1 x = H32.logxor (rotate_right x 6ul) (H32.logxor (rotate_right x 11ul) (rotate_right x 25ul))

[@"substitute"]
private val _sigma0: x:uint32_ht -> Tot uint32_ht
[@"substitute"]
let _sigma0 x = H32.logxor (rotate_right x 7ul) (H32.logxor (rotate_right x 18ul) (H32.shift_right x 3ul))

[@"substitute"]
private val _sigma1: x:uint32_ht -> Tot uint32_ht
[@"substitute"]
let _sigma1 x = H32.logxor (rotate_right x 17ul) (H32.logxor (rotate_right x 19ul) (H32.shift_right x 10ul))


#reset-options " --max_fuel 0 --z3rlimit 10"

[@"substitute"]
private val constants_set_k:
  k:uint32_p{length k = v size_k_w} ->
  Stack unit
        (requires (fun h -> live h k))
        (ensures (fun h0 _ h1 -> live h1 k /\ modifies_1 k h0 h1
                 /\ (let seq_k = Hacl.Spec.Endianness.reveal_h32s (as_seq h1 k) in
                   seq_k == Spec.k)))

[@"substitute"]
let constants_set_k k = hupd_64 k
  (u32_to_h32 0x428a2f98ul) (u32_to_h32 0x71374491ul) (u32_to_h32 0xb5c0fbcful) (u32_to_h32 0xe9b5dba5ul)
  (u32_to_h32 0x3956c25bul) (u32_to_h32 0x59f111f1ul) (u32_to_h32 0x923f82a4ul) (u32_to_h32 0xab1c5ed5ul)
  (u32_to_h32 0xd807aa98ul) (u32_to_h32 0x12835b01ul) (u32_to_h32 0x243185beul) (u32_to_h32 0x550c7dc3ul)
  (u32_to_h32 0x72be5d74ul) (u32_to_h32 0x80deb1feul) (u32_to_h32 0x9bdc06a7ul) (u32_to_h32 0xc19bf174ul)
  (u32_to_h32 0xe49b69c1ul) (u32_to_h32 0xefbe4786ul) (u32_to_h32 0x0fc19dc6ul) (u32_to_h32 0x240ca1ccul)
  (u32_to_h32 0x2de92c6ful) (u32_to_h32 0x4a7484aaul) (u32_to_h32 0x5cb0a9dcul) (u32_to_h32 0x76f988daul)
  (u32_to_h32 0x983e5152ul) (u32_to_h32 0xa831c66dul) (u32_to_h32 0xb00327c8ul) (u32_to_h32 0xbf597fc7ul)
  (u32_to_h32 0xc6e00bf3ul) (u32_to_h32 0xd5a79147ul) (u32_to_h32 0x06ca6351ul) (u32_to_h32 0x14292967ul)
  (u32_to_h32 0x27b70a85ul) (u32_to_h32 0x2e1b2138ul) (u32_to_h32 0x4d2c6dfcul) (u32_to_h32 0x53380d13ul)
  (u32_to_h32 0x650a7354ul) (u32_to_h32 0x766a0abbul) (u32_to_h32 0x81c2c92eul) (u32_to_h32 0x92722c85ul)
  (u32_to_h32 0xa2bfe8a1ul) (u32_to_h32 0xa81a664bul) (u32_to_h32 0xc24b8b70ul) (u32_to_h32 0xc76c51a3ul)
  (u32_to_h32 0xd192e819ul) (u32_to_h32 0xd6990624ul) (u32_to_h32 0xf40e3585ul) (u32_to_h32 0x106aa070ul)
  (u32_to_h32 0x19a4c116ul) (u32_to_h32 0x1e376c08ul) (u32_to_h32 0x2748774cul) (u32_to_h32 0x34b0bcb5ul)
  (u32_to_h32 0x391c0cb3ul) (u32_to_h32 0x4ed8aa4aul) (u32_to_h32 0x5b9cca4ful) (u32_to_h32 0x682e6ff3ul)
  (u32_to_h32 0x748f82eeul) (u32_to_h32 0x78a5636ful) (u32_to_h32 0x84c87814ul) (u32_to_h32 0x8cc70208ul)
  (u32_to_h32 0x90befffaul) (u32_to_h32 0xa4506cebul) (u32_to_h32 0xbef9a3f7ul) (u32_to_h32 0xc67178f2ul)


#reset-options " --max_fuel 0 --z3rlimit 10"

[@"substitute"]
val constants_set_h_0:
  hash:uint32_p{length hash = v size_hash_w} ->
  Stack unit
    (requires (fun h -> live h hash))
    (ensures (fun h0 _ h1 -> live h1 hash /\ modifies_1 hash h0 h1
             /\ (let seq_h_0 = Hacl.Spec.Endianness.reveal_h32s (as_seq h1 hash) in
                seq_h_0 == Spec.h_0)))

[@"substitute"]
let constants_set_h_0 hash = hupd_8 hash
  (u32_to_h32 0x6a09e667ul) (u32_to_h32 0xbb67ae85ul) (u32_to_h32 0x3c6ef372ul) (u32_to_h32 0xa54ff53aul)
  (u32_to_h32 0x510e527ful) (u32_to_h32 0x9b05688cul) (u32_to_h32 0x1f83d9abul) (u32_to_h32 0x5be0cd19ul)


#reset-options " --max_fuel 0 --z3rlimit 20"

[@ "substitute"]
private
val ws_part_1_core:
  ws_w    :uint32_p {length ws_w = v size_ws_w} ->
  block_w :uint32_p {length block_w = v size_block_w /\ disjoint ws_w block_w} ->
  i:UInt32.t{UInt32.v i < 16} ->
  Stack unit
        (requires (fun h -> live h ws_w /\ live h block_w /\
                  (let seq_ws = reveal_h32s (as_seq h ws_w) in
                  let seq_block = reveal_h32s (as_seq h block_w) in
                  (forall (j:nat). {:pattern (Seq.index seq_ws j)} j < UInt32.v i ==> Seq.index seq_ws j == Spec.ws seq_block j))))
        (ensures  (fun h0 r h1 -> live h1 ws_w /\ live h0 ws_w
                  /\ live h1 block_w /\ live h0 block_w /\ modifies_1 ws_w h0 h1 /\
                  as_seq h1 block_w == as_seq h0 block_w
                  /\ (let w = reveal_h32s (as_seq h1 ws_w) in
                  let b = reveal_h32s (as_seq h0 block_w) in
                  (forall (j:nat). {:pattern (Seq.index w j)} j < UInt32.v i+1 ==> Seq.index w j == Spec.ws b j))))

#reset-options " --max_fuel 0 --z3rlimit 100"

[@ "substitute"]
let ws_part_1_core ws_w block_w t =
  (**) let h0 = ST.get() in
  (**) let h = ST.get() in
  let b = block_w.(t) in
  ws_w.(t) <- b;
  (**) let h1 = ST.get() in
  (**) let h' = ST.get() in
  (**) no_upd_lemma_1 h0 h1 ws_w block_w;
  (**) Lemmas.lemma_spec_ws_def (reveal_h32s (as_seq h block_w)) (UInt32.v t);
  (**) assert(Seq.index (as_seq h1 ws_w) (UInt32.v t) == Seq.index (as_seq h block_w) (UInt32.v t))

[@"substitute"]
private val ws_part_1:
  ws_w    :uint32_p {length ws_w = v size_ws_w} ->
  block_w :uint32_p {length block_w = v size_block_w /\ disjoint ws_w block_w} ->
  Stack unit
        (requires (fun h -> live h ws_w /\ live h block_w))
        (ensures  (fun h0 r h1 -> live h1 ws_w /\ live h0 ws_w
                  /\ live h1 block_w /\ live h0 block_w /\ modifies_1 ws_w h0 h1
                  /\ (let w = reveal_h32s (as_seq h1 ws_w) in
                  let b = reveal_h32s (as_seq h0 block_w) in
                  (forall (i:nat). {:pattern (Seq.index w i)} i < 16 ==> Seq.index w i == Spec.ws b i))))

#reset-options " --max_fuel 0 --z3rlimit 200"

[@"substitute"]
let ws_part_1 ws_w block_w =
  (**) let h0 = ST.get() in
  let inv (h1: HS.mem) (i: nat) : Type0 =
    i <= 16 /\ live h1 ws_w /\ live h1 block_w /\ modifies_1 ws_w h0 h1 /\
    as_seq h1 block_w == as_seq h0 block_w
    /\ (let seq_block = reveal_h32s (as_seq h0 block_w) in
       let w = reveal_h32s (as_seq h1 ws_w) in
    (forall (j:nat). {:pattern (Seq.index w j)} j < i ==> Seq.index w j == Spec.ws seq_block j))
  in
  let f' (t:uint32_t {v t < 16}) :
    Stack unit
      (requires (fun h -> inv h (UInt32.v t)))
      (ensures (fun h_1 _ h_2 -> inv h_2 (UInt32.v t + 1)))
    =
    ws_part_1_core ws_w block_w t
  in
  (**) Lemmas.lemma_modifies_0_is_modifies_1 h0 ws_w;
  for 0ul 16ul inv f';
  (**) let h1 = ST.get() in ()


#reset-options " --max_fuel 0 --z3rlimit 20"

[@ "substitute"]
private
val ws_part_2_core:
  ws_w    :uint32_p {length ws_w = v size_ws_w} ->
  block_w :uint32_p {length block_w = v size_block_w /\ disjoint ws_w block_w} ->
  i:UInt32.t{16 <= UInt32.v i /\ UInt32.v i < 64} ->
  Stack unit
        (requires (fun h -> live h ws_w /\ live h block_w /\
                  (let w = reveal_h32s (as_seq h ws_w) in
                  let b = reveal_h32s (as_seq h block_w) in
                  (forall (j:nat). {:pattern (Seq.index w j)} j < UInt32.v i ==> Seq.index w j == Spec.ws b j))))
        (ensures  (fun h0 r h1 -> live h1 ws_w /\ live h0 ws_w
                  /\ live h1 block_w /\ live h0 block_w /\ modifies_1 ws_w h0 h1 /\
                  as_seq h1 block_w == as_seq h0 block_w
                  /\ (let w = reveal_h32s (as_seq h1 ws_w) in
                  let b = reveal_h32s (as_seq h0 block_w) in
                  (forall (j:nat). {:pattern (Seq.index w j)} j < UInt32.v i+1 ==> Seq.index w j == Spec.ws b j))))

#reset-options " --max_fuel 0 --z3rlimit 100"

[@ "substitute"]
let ws_part_2_core ws_w block_w t =
  (**) let h0 = ST.get () in
  let t16 = ws_w.(t -^ 16ul) in
  let t15 = ws_w.(t -^ 15ul) in
  let t7  = ws_w.(t -^ 7ul) in
  let t2  = ws_w.(t -^ 2ul) in
  ws_w.(t) <- H32.((_sigma1 t2) +%^ (t7 +%^ ((_sigma0 t15) +%^ t16)));
  (**) let h1 = ST.get () in
  (**) no_upd_lemma_1 h0 h1 ws_w block_w;
  (**) Lemmas.lemma_spec_ws_def2 (reveal_h32s (as_seq h0 block_w)) (UInt32.v t);
  (**) assert(Seq.index (reveal_h32s (as_seq h1 ws_w)) (UInt32.v t) == Spec.ws (reveal_h32s (as_seq h0 block_w)) (UInt32.v t))


#reset-options " --max_fuel 0 --z3rlimit 20"

[@"substitute"]
private val ws_part_2:
  ws_w    :uint32_p {length ws_w = v size_ws_w} ->
  block_w :uint32_p {length block_w = v size_block_w /\ disjoint ws_w block_w} ->
  Stack unit
        (requires (fun h -> live h ws_w /\ live h block_w
                  /\ (let w = reveal_h32s (as_seq h ws_w) in
                  let b = reveal_h32s (as_seq h block_w) in
                  (forall (i:nat). {:pattern (Seq.index w i)} i < 16 ==> Seq.index w i == Spec.ws b i))))
        (ensures  (fun h0 r h1 -> live h1 ws_w /\ live h0 ws_w
                  /\ live h1 block_w /\ live h0 block_w /\ modifies_1 ws_w h0 h1
                  /\ (let w = reveal_h32s (as_seq h1 ws_w) in
                  let b = reveal_h32s (as_seq h0 block_w) in
                  (forall (i:nat). {:pattern (Seq.index w i)} i < 64 ==> Seq.index w i == Spec.ws b i))))

#reset-options " --max_fuel 0 --z3rlimit 200"

[@"substitute"]
let ws_part_2 ws_w block_w =
  (**) let h0 = ST.get() in
  let inv (h1: HS.mem) (i: nat) : Type0 =
    live h1 ws_w /\ live h1 block_w /\ modifies_1 ws_w h0 h1 /\ 16 <= i /\ i <= 64
    /\ as_seq h1 block_w == as_seq h0 block_w
    /\ (let seq_block = reveal_h32s (as_seq h0 block_w) in
       let w = reveal_h32s (as_seq h1 ws_w) in
    (forall (j:nat). {:pattern (Seq.index w j)} j < i ==> Seq.index w j == Spec.ws seq_block j))
  in
  let f' (t:uint32_t {16 <= v t /\ v t < v size_ws_w}) :
    Stack unit
      (requires (fun h -> inv h (UInt32.v t)))
      (ensures (fun h_1 _ h_2 -> inv h_2 (UInt32.v t + 1)))
    =
    ws_part_2_core ws_w block_w t
  in
  (**) Lemmas.lemma_modifies_0_is_modifies_1 h0 ws_w;
  for 16ul 64ul inv f';
  (**) let h1 = ST.get() in ()


#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
private val ws:
  ws_w    :uint32_p {length ws_w = v size_ws_w} ->
  block_w :uint32_p {length block_w = v size_block_w /\ disjoint ws_w block_w} ->
  Stack unit
        (requires (fun h -> live h ws_w /\ live h block_w))
        (ensures  (fun h0 r h1 -> live h1 ws_w /\ live h0 ws_w /\ live h1 block_w /\ live h0 block_w
                  /\ modifies_1 ws_w h0 h1
                  /\ (let w = reveal_h32s (as_seq h1 ws_w) in
                  let b = reveal_h32s (as_seq h0 block_w) in
                  (forall (i:nat). {:pattern (Seq.index w i)} i < 64 ==> Seq.index w i == Spec.ws b i))))

#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
let ws ws_w block_w =
  ws_part_1 ws_w block_w;
  ws_part_2 ws_w block_w


#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
private val shuffle_core:
  hash_w :uint32_p {length hash_w = v size_hash_w} ->
  block_w:uint32_p {length block_w = v size_block_w} ->
  ws_w   :uint32_p {length ws_w = v size_ws_w} ->
  k_w    :uint32_p {length k_w = v size_k_w} ->
  t      :uint32_t {v t < v size_k_w} ->
  Stack unit
        (requires (fun h -> live h hash_w /\ live h ws_w /\ live h k_w /\ live h block_w /\
          reveal_h32s (as_seq h k_w) == Spec.k /\
          (let w = reveal_h32s (as_seq h ws_w) in
           let b = reveal_h32s (as_seq h block_w) in
           (forall (i:nat). {:pattern (Seq.index w i)} i < 64 ==> Seq.index w i == Spec.ws b i)) ))
        (ensures  (fun h0 r h1 -> live h0 hash_w /\ live h0 ws_w /\ live h0 k_w /\ live h0 block_w
          /\ live h1 hash_w /\ modifies_1 hash_w h0 h1
                  /\ (let seq_hash_0 = reveal_h32s (as_seq h0 hash_w) in
                  let seq_hash_1 = reveal_h32s (as_seq h1 hash_w) in
                  let seq_block = reveal_h32s (as_seq h0 block_w) in
                  seq_hash_1 == Spec.shuffle_core seq_block seq_hash_0 (U32.v t))))

#reset-options "--max_fuel 0  --z3rlimit 50"

[@"substitute"]
let shuffle_core hash block ws k t =
  let a = hash.(0ul) in
  let b = hash.(1ul) in
  let c = hash.(2ul) in
  let d = hash.(3ul) in
  let e = hash.(4ul) in
  let f = hash.(5ul) in
  let g = hash.(6ul) in
  let h = hash.(7ul) in

  (* Perform computations *)
  let kt = k.(t) in
  let wst = ws.(t) in
  let t1 = H32.(h +%^ (_Sigma1 e) +%^ (_Ch e f g) +%^ kt +%^ wst) in
  let t2 = H32.((_Sigma0 a) +%^ (_Maj a b c)) in

  (* Store the new working hash in the state *)
  hupd_8 hash H32.(t1 +%^ t2) a b c H32.(d +%^ t1) e f g


#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
private val shuffle:
  hash_w :uint32_p {length hash_w = v size_hash_w} ->
  block_w:uint32_p {length block_w = v size_block_w /\ disjoint block_w hash_w} ->
  ws_w   :uint32_p {length ws_w = v size_ws_w /\ disjoint ws_w hash_w} ->
  k_w    :uint32_p {length k_w = v size_k_w /\ disjoint k_w hash_w} ->
  Stack unit
        (requires (fun h -> live h hash_w /\ live h ws_w /\ live h k_w /\ live h block_w /\
                  reveal_h32s (as_seq h k_w) == Spec.k /\
                  (let w = reveal_h32s (as_seq h ws_w) in
                  let b = reveal_h32s (as_seq h block_w) in
                  (forall (i:nat). {:pattern (Seq.index w i)} i < 64 ==> Seq.index w i == Spec.ws b i)) ))
        (ensures  (fun h0 r h1 -> live h1 hash_w /\ modifies_1 hash_w h0 h1 /\ live h0 block_w
                  /\ live h0 hash_w
                  /\ (let seq_hash_0 = reveal_h32s (as_seq h0 hash_w) in
                  let seq_hash_1 = reveal_h32s (as_seq h1 hash_w) in
                  let seq_block = reveal_h32s (as_seq h0 block_w) in
                  seq_hash_1 == Spec.shuffle seq_hash_0 seq_block)))

#reset-options "--max_fuel 0  --z3rlimit 100"

[@"substitute"]
let shuffle hash block ws k =
  (**) let h0 = ST.get() in
  let inv (h1: HS.mem) (i: nat) : Type0 =
    live h1 hash /\ modifies_1 hash h0 h1 /\ i <= v size_ws_w
    /\ (let seq_block = reveal_h32s (as_seq h0 block) in
    reveal_h32s (as_seq h1 hash) == repeat_range_spec 0 i (Spec.shuffle_core seq_block) (reveal_h32s (as_seq h0 hash)))
  in
  let f' (t:uint32_t {v t < v size_ws_w}) :
    Stack unit
      (requires (fun h -> inv h (UInt32.v t)))
      (ensures (fun h_1 _ h_2 -> inv h_2 (UInt32.v t + 1)))
    =
    shuffle_core hash block ws k t;
    (**) C.Loops.lemma_repeat_range_spec 0 (UInt32.v t + 1) (Spec.shuffle_core (reveal_h32s (as_seq h0 block))) (reveal_h32s (as_seq h0 hash))
  in
  (**) C.Loops.lemma_repeat_range_0 0 0 (Spec.shuffle_core (reveal_h32s (as_seq h0 block))) (reveal_h32s (as_seq h0 hash));
  for 0ul size_ws_w inv f'


#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
private val sum_hash:
  hash_0:uint32_p{length hash_0 = v size_hash_w} ->
  hash_1:uint32_p{length hash_1 = v size_hash_w /\ disjoint hash_0 hash_1} ->
  Stack unit
    (requires (fun h -> live h hash_0 /\ live h hash_1))
    (ensures  (fun h0 _ h1 -> live h0 hash_0 /\ live h1 hash_0 /\ live h0 hash_1 /\ modifies_1 hash_0 h0 h1
              /\ (let new_seq_hash_0 = as_seq h1 hash_0 in
              let seq_hash_0 = as_seq h0 hash_0 in
              let seq_hash_1 = as_seq h0 hash_1 in
              new_seq_hash_0 == Spec.Lib.map2 (fun x y -> H32.(x +%^ y)) seq_hash_0 seq_hash_1 )))

#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
let sum_hash hash_0 hash_1 =
  C.Loops.in_place_map2 hash_0 hash_1 size_hash_w (fun x y -> H32.(x +%^ y))


type block = b:uint32_p{length b == 16}
type table = b:uint32_p{length b == 64}
type hash  =  b:uint32_p{length b == 8}
type u32 = UInt32.t
type u32seq n = s:Seq.seq u32{Seq.length s == n}
type state_spec = {
  k: u32seq 64;
  h0: u32seq 8;
  data: u32seq 16;
  ws: u32seq 64;
  whash: u32seq 8;
  whash_copy: u32seq 8;
  counter: u32
}

let size_state  = 64ul (* k *) +^ 8ul (* h0 *) +^ 16ul (* data_w *) +^ 64ul (* ws_w *) +^ 
	          8ul  (* whash *) +^ 8ul (* whash_copy *) +^ 1ul (* counter *)
type state = b:uint32_p{length b == v size_state}

unfold let get_k (s:state) = Buffer.sub s 0ul 64ul
unfold let get_h0 (s:state) = Buffer.sub s 64ul 8ul
unfold let get_data (s:state) = Buffer.sub s 72ul 16ul
unfold let get_ws (s:state) = Buffer.sub s 88ul 64ul
unfold let get_whash (s:state) = Buffer.sub s 152ul 8ul
unfold let get_whash_copy (s:state) = Buffer.sub s 160ul 8ul
unfold let get_counter (s:state) = Buffer.sub s 168ul 1ul

#reset-options "--max_fuel 0  --z3rlimit 50"

let as_spec (h:mem) (s:state) : GTot (spec:state_spec{
  spec.k == as_seq h (get_k s) /\ 
  spec.h0 == as_seq h (get_h0 s) /\ 
  spec.data == as_seq h (get_data s) /\ 
  spec.ws == as_seq h (get_ws s) /\ 
  spec.whash == as_seq h (get_whash s) /\ 
  spec.whash_copy == as_seq h (get_whash_copy s) /\ 
  spec.counter == Seq.index (as_seq h (get_counter s)) 0
}) = {
  k = as_seq h (get_k s);
  h0 = as_seq h (get_h0 s);
  data = as_seq h (get_data s);
  ws = as_seq h (get_ws s);
  whash = as_seq h (get_whash s);
  whash_copy = as_seq h (get_whash_copy s);
  counter = Seq.index (as_seq h (get_counter s)) 0;
}

let state_inv s = 
     let k = get_k s in
     let h0 = get_h0 s in
     let data = get_data s in
     let ws = get_ws s in
     let whash = get_whash s in
     let whash_copy = get_whash_copy s in
     let counter = get_counter s in
     length k == 64 /\
     length h0 == 8 /\
     length data == 16 /\
     length ws == 64 /\
     length whash == 8 /\
     length whash_copy == 8 /\
     length counter == 1 /\
     disjoint k h0 /\ disjoint k data /\ disjoint k ws /\ disjoint k whash /\ disjoint k whash_copy /\ disjoint k counter /\
     disjoint h0 data /\ disjoint h0 ws /\ disjoint h0 whash /\ disjoint h0 whash_copy /\ disjoint h0 counter /\
     disjoint data ws /\ disjoint data whash /\ disjoint data whash_copy /\ disjoint data counter /\
     disjoint ws whash /\ disjoint ws whash_copy /\ disjoint ws counter /\
     disjoint whash whash_copy /\ disjoint whash counter /\
     disjoint whash_copy counter /\
     frameOf k == frameOf h0 /\
     frameOf k == frameOf data /\
     frameOf k == frameOf ws /\
     frameOf k == frameOf whash /\
     frameOf k == frameOf whash_copy /\
     frameOf k == frameOf counter

let state_inv_st s h =
     state_inv s /\
     live h s /\
    (let spec_k = as_seq h (get_k s) in
     let spec_h0 = as_seq h (get_h0 s) in
     spec_k == Spec.k /\
     spec_h0 == Spec.h_0)


#reset-options "--max_fuel 0 --z3rlimit 20"

[@"c_inline"]
val alloc:
  unit ->
  StackInline (st: state)
    (requires (fun h0 -> True))
    (ensures (fun h0 st h1 -> state_inv st /\
	     (st `unused_in` h0) /\ live h1 st /\ modifies_0 h0 h1 /\ frameOf st == h1.tip
             /\ Map.domain h1.h == Map.domain h0.h))

[@"c_inline"]
let alloc () = Buffer.create (u32_to_h32 0ul) size_state


#reset-options "--max_fuel 0  --z3rlimit 50"

val init:
  st:state -> Stack unit
    (requires (fun h0 -> live h0 st /\ state_inv st))
    (ensures  (fun h0 r h1 -> state_inv_st st h1 /\ modifies_1 st h0 h1 /\
		 (let spec_c = Seq.index (as_seq h1 (get_counter st)) 0 in
		  v spec_c == 0)))
let init st =
  let k = get_k st in
  let h_0 = get_h0 st in 
  let ctr = get_counter st in
  constants_set_k k;
  constants_set_h_0 h_0;
  ctr.(0ul) <- 0ul



#reset-options "--max_fuel 0  --z3rlimit 100"

[@"substitute"]
private val copy_whash:
  st: state -> Stack unit
        (requires (fun h0 -> state_inv_st st h0))
        (ensures  (fun h0 _ h1 -> state_inv_st st h1 /\ 
		    (let whash = get_whash st in
		     let whash_copy = get_whash_copy st in
		     modifies_1 whash_copy h0 h1 /\
		     as_seq h1 whash_copy == as_seq h0 whash)))
#reset-options "--max_fuel 0  --z3rlimit 20"
[@"substitute"]
let copy_whash st = 
  let whash = get_whash st in
  let whash_copy = get_whash_copy st in
  Buffer.blit whash 0ul whash_copy 0ul size_hash_w


#reset-options "--max_fuel 0  --z3rlimit 20"
 
[@"substitute"]
private val update_core:
  st:state -> Stack unit
        (requires (fun h0 -> state_inv_st st h0))
        (ensures  (fun h0 r h1 -> state_inv_st st h1 /\
		     modifies_1 st h0 h1 /\ 
                  (let spec0 = as_spec h0 st in
		   let spec1 = as_spec h1 st in
		   (forall (i:nat). {:pattern (Seq.index spec1.ws i)} i < 64 ==> 
		       Seq.index spec1.ws i == Spec.ws spec0.data i) /\
		   spec0.counter == spec1.counter /\ 
		   spec1.whash == Spec.update_core spec0.whash spec0.data)))

#reset-options "--max_fuel 0  --z3rlimit 100"

[@"substitute"]
let update_core st = 
  let whash = get_whash st in
  let whash_copy = get_whash_copy st in
  let data = get_data st in
  let ws_buf = get_ws st in
  let k = get_k st in
  ws ws_buf data;
  copy_whash st ;
  shuffle whash_copy data ws_buf k;
  sum_hash whash whash_copy


#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
val counter_increment:
  counter_w :uint32_p{length counter_w = v size_count_w} ->
  Stack unit
        (requires (fun h -> live h counter_w
                  /\ (let counter = Seq.index (as_seq h counter_w) 0 in
                  H32.v counter < (pow2 32 - 1))))
        (ensures  (fun h0 _ h1 -> live h1 counter_w /\ live h0 counter_w /\ modifies_1 counter_w h0 h1
                  /\ (let counter_0 = Seq.index (as_seq h0 counter_w) 0 in
                  let counter_1 = Seq.index (as_seq h1 counter_w) 0 in
                  H32.v counter_1 = H32.v counter_0 + 1 /\ H32.v counter_1 < pow2 32)))

#reset-options "--max_fuel 0  --z3rlimit 50"

[@"substitute"]
let counter_increment counter_w =
  let c0 = counter_w.(0ul) in
  let one = u32_to_h32 1ul in
  counter_w.(0ul) <- H32.(c0 +%^ one)


#reset-options "--max_fuel 0  --z3rlimit 50"

val update:
  st    : state -> 
  data  : uint8_p  {length data = v size_block /\ disjoint st data} ->
  Stack unit
        (requires (fun h0 -> state_inv_st st h0 /\ live h0 data 
                  /\ (let counter = Seq.index (as_seq h0 (get_counter st)) 0 in
                     v counter < (pow2 32 - 1))))
        (ensures  (fun h0 r h1 -> state_inv_st st h1 /\ live h1 data /\ modifies_1 st h0 h1 /\
                     (let spec0 = as_spec h0 st in 
		      let spec1 = as_spec h1 st in 
		      let data_block0 = as_seq h0 data in
                      H32.v spec1.counter = H32.v spec0.counter + 1 /\ 
		      H32.v spec1.counter < pow2 32 /\
                      spec1.whash == Spec.update spec0.whash data_block0)))

#reset-options "--max_fuel 0 --max_ifuel 0 --z3rlimit 100"

let update st data_block =
    let data_w = get_data st in
    let counter = get_counter st in
    uint32s_from_be_bytes data_w data_block size_block_w;
    update_core st;
    counter_increment counter


#reset-options "--z3rlimit 200 --max_fuel 0 --max_ifuel 0"

let inv_multi st data n h0 hi (i:nat{0 <= i /\ i <= n /\ length data >= n * (v size_block)}) =
         state_inv_st st hi /\ 
	 live hi data /\ 
	 disjoint st data /\
	 modifies_1 st h0 hi
      /\ (let data_seq = as_seq h0 data in
	 let sizei = i * v size_block in
	 let data_blocks = Seq.slice data_seq 0 sizei in 
	 let spec0 = as_spec h0 st in
	 let speci = as_spec hi st in
         H32.v speci.counter == H32.v spec0.counter + i /\ 
	 H32.v speci.counter < pow2 32 - n + i /\
         speci.whash == Spec.update_multi spec0.whash data_blocks) 

let updatei st data n h0 
    (i:UInt32.t{0 <= v i /\ v i < n /\ length data >= n * (v size_block)}) 
    : Stack unit 
     (requires (fun h -> inv_multi st data n h0 h (v i)))
     (ensures  (fun _ _ h1 -> inv_multi st data n h0 h1 (v i + 1))) =
    admit();
    let h = ST.get() in
    let blocks = Buffer.sub data 0ul (i *^ size_block) in
    let b      = Buffer.sub data (i *^ size_block) size_block in
    Spec.update_update_multi_append
      (as_seq h0 (get_whash st))
      (as_seq h blocks)
      (as_seq h b);
    let blocks1 = Buffer.sub data 0ul ((i +^ 1ul) *^ size_block) in
    Seq.lemma_eq_intro (Seq.append (as_seq h blocks) (as_seq h b)) (as_seq h blocks1);
    update st b


val update_multi:
  st    : state -> 
  data  : uint8_p  {disjoint st data} ->
  n     : uint32_t{length data == v n * v size_block /\ 
		   length data % (v size_block) == 0} ->
  Stack unit
        (requires (fun h0 -> state_inv_st st h0 /\ live h0 data 
                  /\ (let counter = Seq.index (as_seq h0 (get_counter st)) 0 in
                     v counter < (pow2 32 - v n))))
        (ensures  (fun h0 r h1 -> inv_multi st data (v n) h0 h1 (v n)))
	
#reset-options "--z3rlimit 100 --max_fuel 0 --max_ifuel 0"

let update_multi st data n =
  admit();
  let h0 = ST.get() in
  let inv = inv_multi st data (v n) h0 in
  let f = updatei st data (v n) h0 in
  for 0ul n inv f


#reset-options "--max_fuel 0  --z3rlimit 50"

inline_for_extraction
let pad0_length (len:uint32_t{v len + 1 + v size_len_8 < pow2 32}) : Tot (n:uint32_t{v n = Spec.pad0_length (v len)}) =
  (size_block -^ (len +^ size_len_8 +^ 1ul) %^ size_block) %^ size_block


#reset-options "--max_fuel 0  --z3rlimit 50"

inline_for_extraction
let encode_length (count:uint32_ht) (len:uint32_t) : Tot (l:uint64_ht{H64.v l = (H32.v count * v size_block + v len) * 8}) =
  let l_0 = H64.((h32_to_h64 count) *%^ (u32_to_h64 size_block)) in
  let l_1 = u32_to_h64 len in
  H64.((l_0 +^ l_1) *%^ (u32_to_h64 8ul))

let padded_length (len:u32{v len < v size_block}) : 
		  Tot (plen:u32{(v plen == v size_block \/
		    		 v plen == v size_block + v size_block) /\
				 v plen > v len + v size_len_8}) =
    if (len <^ 56ul) then size_block else size_block +^ size_block

#reset-options "--max_fuel 0  --z3rlimit 30"
val update_last:
  st    :state ->
  data  :uint8_p  {disjoint st data} ->
  len   :uint32_t {v len == length data /\ v len < v size_block} ->
  Stack unit
        (requires (fun h0 -> state_inv_st st h0 /\ live h0 data /\ 
		  (let spec = as_spec h0 st in 
  		   let prevlen = (v spec.counter) * (v size_block) in
		   prevlen % (v size_block) == 0 /\
		   v size_block + prevlen < Spec.max_input_len_8 /\
                   v spec.counter < (pow2 32 - 2))))
        (ensures  (fun h0 r h1 -> state_inv_st st h1 /\ live h1 data /\ modifies_1 st h0 h1 /\ 
			     true (*
		             (let spec0 = as_spec h0 st in 
			      let spec1 = as_spec h1 st in 
			      let prevlen = (v spec0.counter) * (v size_block) in
			      let data_seq = as_seq h0 data in
			      spec1.whash == Spec.update_last spec0.whash prevlen data_seq)*)))

#reset-options "--max_fuel 0 --initial_ifuel 1 --max_ifuel 1 --z3rlimit 200"

let update_last st data len =
  push_frame();
  
  let blocks = Buffer.create (uint8_to_sint8 0uy) (size_block +^ size_block) in
  Buffer.blit data 0ul blocks 0ul len;
  blocks.(len) <- 0x80uy;
  let plen = padded_length len in
  let n = (get_counter st).(0ul) in
  let encodedlen = encode_length n len in
  let lenb = Buffer.sub blocks (plen -^ size_len_8) size_len_8 in
  Hacl.Endianness.hstore64_be lenb encodedlen;
  if (plen =^ 64ul) then 
    let block1 = Buffer.sub blocks 0ul size_block in
    update st block1
  else update_multi st blocks 2ul;
  pop_frame()



(*
								   
#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
val set_pad_part1:
  buf1 :uint8_p {length buf1 = 1} ->
  Stack unit
        (requires (fun h0 -> live h0 buf1))
        (ensures  (fun h0 _ h1 -> live h0 buf1 /\ live h1 buf1 /\ modifies_1 buf1 h0 h1
                             /\ (let seq_buf1 = reveal_sbytes (as_seq h1 buf1) in
                             seq_buf1 = Seq.create 1 0x80uy)))

#reset-options "--max_fuel 0 --z3rlimit 50"

[@"substitute"]
let set_pad_part1 buf1 =
  Buffer.upd buf1 0ul (u8_to_h8 0x80uy);
  (**) let h = ST.get () in
  (**) Seq.lemma_eq_intro (as_seq h buf1) (Seq.create 1 (u8_to_h8 0x80uy))

#reset-options "--max_fuel 0  --z3rlimit 50"

[@"substitute"]
val set_pad_part2:
  buf2       :uint8_p{length buf2 = v size_len_8} ->
  encodedlen :uint64_ht ->
  Stack unit
        (requires (fun h0 -> live h0 buf2))
        (ensures  (fun h0 _ h1 -> live h0 buf2 /\ live h1 buf2 /\ modifies_1 buf2 h0 h1
                  /\ (let seq_buf2 = reveal_sbytes (as_seq h1 buf2) in
                  seq_buf2 == Endianness.big_bytes size_len_8 (H64.v encodedlen))))

#reset-options "--max_fuel 0  --z3rlimit 30"

[@"substitute"]
let set_pad_part2 buf2 encodedlen =
  Hacl.Endianness.hstore64_be buf2 encodedlen;
  (**) let h = ST.get () in
  (**) Lemmas.lemma_eq_endianness h buf2 encodedlen


#reset-options "--max_fuel 0  --z3rlimit 50"

[@"substitute"]
val pad:
  padding :uint8_p ->
  n       :uint32_ht ->
  len     :uint32_t {(v len + v size_len_8 + 1) < (2 * v size_block)
                     /\ H32.v n * v size_block + v len < U64.v max_input_len
                     /\ length padding = (1 + v (pad0_length len) + v size_len_8)
                     /\ (length padding + v len) % v size_block = 0} ->
  Stack unit
        (requires (fun h0 -> live h0 padding
                  /\ (let seq_padding = reveal_sbytes (as_seq h0 padding) in
                  seq_padding == Seq.create (1 + v (pad0_length len) + v size_len_8) 0uy )))
        (ensures  (fun h0 _ h1 -> live h0 padding /\ live h1 padding /\ modifies_1 padding h0 h1
                  /\ (let seq_padding = reveal_sbytes (as_seq h1 padding) in
                  seq_padding == Spec.pad (H32.v n * v size_block) (v len))))

#reset-options "--max_fuel 0  --z3rlimit 100"

[@"substitute"]
let pad padding n len =

  (* Compute the length of zeros *)
  let pad0len = pad0_length len in

  (* Retreive the different parts of the padding *)
  let buf1 = Buffer.sub padding 0ul 1ul in
  let zeros = Buffer.sub padding 1ul pad0len in
  let buf2 = Buffer.sub padding (1ul +^ pad0len) size_len_8 in

  (* Compute and encode the total length *)
  let encodedlen = encode_length n len in

  let h0 = ST.get () in
  (**) Seq.lemma_eq_intro (reveal_sbytes (as_seq h0 zeros)) (Seq.create (v pad0len) 0uy);
  (**) assert(reveal_sbytes (as_seq h0 zeros) == Seq.create (v pad0len) 0uy);

  (* Set the first byte of the padding *)
  set_pad_part1 buf1;

  (* Encode the total length at the end of the padding *)
  set_pad_part2 buf2 encodedlen;

  (* Proof that this is the concatenation of the three parts *)
  let h1 = ST.get () in
  (**) Buffer.no_upd_lemma_2 h0 h1 buf1 buf2 zeros;
  (**) Seq.lemma_eq_intro (reveal_sbytes (as_seq h1 zeros)) (Seq.create (v pad0len) 0uy);
  (**) assert(reveal_sbytes (as_seq h1 zeros) == Seq.create (v pad0len) 0uy);
  (**) assert(reveal_sbytes (as_seq h1 buf1) == Seq.create 1 0x80uy);
  (**) assert(reveal_sbytes (as_seq h1 zeros) == Seq.create (v (pad0_length len)) 0uy);
  (**) assert(reveal_sbytes (as_seq h1 buf2) == Endianness.big_bytes size_len_8 (H64.v encodedlen));
  (**) Lemmas.lemma_sub_append_3 h1 padding 0ul buf1 1ul zeros (1ul +^ pad0len) buf2 (1ul +^ pad0len +^ size_len_8);
  (**) Lemmas.lemma_pad_aux h1 n len buf1 zeros buf2


#reset-options "--max_fuel 0 --initial_ifuel 1 --max_ifuel 1 --z3rlimit 50"

val update_last:
  state :uint32_p {length state = v size_state} ->
  data  :uint8_p  {disjoint state data} ->
  len   :uint32_t {v len = length data /\ (length data + v size_len_8 + 1) < 2 * v size_block} ->
  Stack unit
        (requires (fun h0 -> live h0 state /\ live h0 data
                  /\ (let seq_k = Seq.slice (as_seq h0 state) (U32.v pos_k_w) (U32.(v pos_k_w + v size_k_w)) in
                  let seq_counter = Seq.slice (as_seq h0 state) (U32.v pos_count_w) (U32.(v pos_count_w + v size_count_w)) in
                  let counter = Seq.index seq_counter 0 in
                  let nb = U32.div len size_block in
                  reveal_h32s seq_k == Spec.k /\ H32.v counter < (pow2 32 - 2))))
        (ensures  (fun h0 r h1 -> live h0 state /\ live h0 data /\ live h1 state /\ modifies_1 state h0 h1
                  /\ (let seq_hash_0 = Seq.slice (as_seq h0 state) (U32.v pos_whash_w) (U32.(v pos_whash_w + v size_whash_w)) in
                  let seq_hash_1 = Seq.slice (as_seq h1 state) (U32.v pos_whash_w) (U32.(v pos_whash_w + v size_whash_w)) in
                  let seq_data = reveal_sbytes (as_seq h0 data) in
                  let count = Seq.slice (as_seq h0 state) (U32.v pos_count_w) (U32.v pos_count_w + 1) in
                  let prevlen = U32.(H32.v (Seq.index count 0) * (v size_block)) in
                  (reveal_h32s seq_hash_1) == Spec.update_last (reveal_h32s seq_hash_0) prevlen seq_data)))

#reset-options "--max_fuel 0 --initial_ifuel 1 --max_ifuel 1 --z3rlimit 300"

let update_last state data len =
  (**) assert_norm(pow2 32 = 0x100000000);

  (**) let hinit = ST.get() in
  
  (* Push a new memory frame *)
  (**) push_frame();

  (**) let h00 = ST.get() in

  (* Alocate memory set to zeros for the last two blocks of data *)
  let blocks = Buffer.create (uint8_to_sint8 0uy) (2ul *^ size_block) in

  (**) let h0 = ST.get () in
  (**) assert(reveal_sbytes (as_seq h0 blocks) == Seq.create (2 * v size_block) 0uy);

  (* Verification of how many blocks are necessary *)
  (* Threat model. The length are considered public here ! *)
  let nb = if U32.(len <^ 56ul) then 1ul else 2ul in

  let final_blocks =
    (**) let h1 = ST.get () in
    if U32.(len <^ 56ul) then begin
      (**) assert(v size_block <= length blocks);
      (**) assert(live h1 blocks);
      Buffer.offset blocks size_block end
    else begin
      (**) assert(live h1 blocks);
      blocks end in

  (**) assert(blocks `includes` final_blocks);

  (**) let h1 = ST.get () in

  (**) Seq.lemma_eq_intro (reveal_sbytes (as_seq h1 final_blocks))
                          (if U32.(len <^ 56ul) then
                              Seq.create (v size_block) 0uy
                           else Seq.create (v size_block + v size_block) 0uy);
  (**) Seq.lemma_eq_intro (reveal_sbytes (as_seq h1 final_blocks)) (Seq.create (v nb * v size_block) 0uy);
  (**) assert(reveal_sbytes (as_seq h1 final_blocks) == Seq.create (v nb * v size_block) 0uy);

  (* Copy the data to the final construct *)
  (* Leakage model : allowed because the length is public *)
  Buffer.blit data 0ul final_blocks 0ul len;

  (**) let h2 = ST.get () in
  (**) modifies_subbuffer_1 h1 h2 final_blocks blocks;
  (**) Seq.lemma_eq_intro (as_seq h2 data) (Seq.slice (as_seq h2 data) 0 (v len));
  (**) Seq.lemma_eq_intro (as_seq h2 data) (Seq.slice (as_seq h2 final_blocks) 0 (v len));
  (**) assert(as_seq h2 data == Seq.slice (as_seq h2 final_blocks) 0 (v len));

  (* Compute the final length of the data *)
  let n = state.(pos_count_w) in

  (* Set the padding *)
  let padding = Buffer.offset final_blocks len in
  (**) assert(v len + v size_len_8 + 1 < 2 * v size_block);
  (**) assert(H32.v n * v size_block + v len < U64.v max_input_len);
  (**) assert(length padding = (1 + v (pad0_length len) + v size_len_8));
  (**) assert((length padding + v len) % v size_block = 0);
  (**) Seq.lemma_eq_intro (reveal_sbytes (as_seq h1 padding)) (Seq.create (1 + v (pad0_length len) + v size_len_8) 0uy);
  (**) assert(reveal_sbytes (as_seq h2 padding) == Seq.create (1 + v (pad0_length len) + v size_len_8) 0uy);
  pad padding n len;

  (* Proof that final_blocks = data @| padding *)
  (**) let h3 = ST.get () in
  (**) modifies_subbuffer_1 h2 h3 padding blocks;
  (**) lemma_modifies_1_trans blocks h1 h2 h3;
  (**) assert(disjoint padding data);
  (**) no_upd_lemma_1 h2 h3 padding data;
  (**) Seq.lemma_eq_intro (as_seq h3 (Buffer.sub final_blocks 0ul len)) (Seq.slice (as_seq h3 final_blocks) 0 (v len));
  (**) no_upd_lemma_1 h2 h3 padding (Buffer.sub final_blocks 0ul len);
  (**) assert(reveal_sbytes (as_seq h3 data) == Seq.slice (reveal_sbytes (as_seq h3 final_blocks)) 0 (v len));

  (**) Seq.lemma_eq_intro (as_seq h3 (Buffer.offset final_blocks len)) (Seq.slice (as_seq h3 final_blocks) (v len) (v nb * v size_block));
  (**) Seq.lemma_eq_intro (as_seq h3 padding) (Seq.slice (as_seq h3 final_blocks) (v len) (v nb * v size_block));
  (**) assert(as_seq h3 padding == Seq.slice (as_seq h3 final_blocks) (v len) (v nb * v size_block));
  (**) Lemmas.lemma_sub_append_2 h3 final_blocks 0ul data len padding (nb *^ size_block);
  (**) assert(as_seq h3 final_blocks == Seq.append (as_seq h3 data) (as_seq h3 padding));

  (* Call the update function on one or two blocks *)
  (**) assert(length final_blocks % v size_block = 0 /\ disjoint state data);
  (**) assert(v nb * v size_block = length final_blocks);
  (**) assert(live h3 state /\ live h3 final_blocks);
  (**) assert(let seq_k = Seq.slice (as_seq h3 state) (U32.v pos_k_w) (U32.(v pos_k_w + v size_k_w)) in
              let seq_counter = Seq.slice (as_seq h3 state) (U32.v pos_count_w) (U32.(v pos_count_w + v size_count_w)) in
              let counter = Seq.index seq_counter 0 in
              reveal_h32s seq_k == Spec.k /\ H32.v counter < (pow2 32 - 2));

  update_multi state final_blocks nb;

  (**) let h4 = ST.get() in
  (**) lemma_modifies_0_1' blocks h00 h1 h3;
  (**) lemma_modifies_0_1 state h00 h3 h4;

  (* Pop the memory frame *)
  (**) pop_frame();
  (**) let hfin = ST.get() in
  (**) modifies_popped_1 state hinit h00 h4 hfin


#reset-options "--max_fuel 0  --z3rlimit 20"

[@"substitute"]
val finish_core:
  hash_w :uint32_p {length hash_w = v size_hash_w} ->
  hash   :uint8_p  {length hash = v size_hash /\ disjoint hash_w hash} ->
  Stack unit
        (requires (fun h0 -> live h0 hash_w /\ live h0 hash))
        (ensures  (fun h0 _ h1 -> live h0 hash_w /\ live h0 hash /\ live h1 hash /\ modifies_1 hash h0 h1
                  /\ (let seq_hash_w = reveal_h32s (as_seq h0 hash_w) in
                  let seq_hash = reveal_sbytes (as_seq h1 hash) in
                  seq_hash = Spec.words_to_be (U32.v size_hash_w) seq_hash_w)))

[@"substitute"]
let finish_core hash_w hash = uint32s_to_be_bytes hash hash_w size_hash_w


#reset-options "--max_fuel 0  --z3rlimit 20"

val finish:
  state :uint32_p{length state = v size_state} ->
  hash  :uint8_p{length hash = v size_hash /\ disjoint state hash} ->
  Stack unit
        (requires (fun h0 -> live h0 state /\ live h0 hash))
        (ensures  (fun h0 _ h1 -> live h0 state /\ live h1 hash /\ modifies_1 hash h0 h1
                  /\ (let seq_hash_w = Seq.slice (as_seq h0 state) (U32.v pos_whash_w) (U32.(v pos_whash_w + v size_whash_w)) in
                  let seq_hash = reveal_sbytes (as_seq h1 hash) in
                  seq_hash = Spec.finish (reveal_h32s seq_hash_w))))

let finish state hash =
  let hash_w = Buffer.sub state pos_whash_w size_whash_w in
  finish_core hash_w hash


#reset-options "--max_fuel 0  --z3rlimit 20"

val hash:
  hash :uint8_p {length hash = v size_hash} ->
  input:uint8_p {length input < Spec.max_input_len_8 /\ disjoint hash input} ->
  len  :uint32_t{v len = length input} ->
  Stack unit
        (requires (fun h0 -> live h0 hash /\ live h0 input))
        (ensures  (fun h0 _ h1 -> live h0 input /\ live h0 hash /\ live h1 hash /\ modifies_1 hash h0 h1
                  /\ (let seq_input = reveal_sbytes (as_seq h0 input) in
                  let seq_hash = reveal_sbytes (as_seq h1 hash) in
                  seq_hash == Spec.hash seq_input)))

#reset-options "--max_fuel 0  --z3rlimit 50"

let hash hash input len =

  (**) let hinit = ST.get() in

  (* Push a new memory frame *)
  (**) push_frame ();
  (**) let h0 = ST.get() in

  (* Allocate memory for the hash state *)
  let state = Buffer.create (u32_to_h32 0ul) size_state in
  (**) let h1 = ST.get() in

  (* Compute the number of blocks to process *)
  let n = U32.div len size_block in
  let r = U32.rem len size_block in

  (* Get all full blocks the last block *)
  let input_blocks = Buffer.sub input 0ul (n *%^ size_block) in
  let input_last = Buffer.sub input (n *%^ size_block) r in

  (* Initialize the hash function *)
  init state;
  (**) let h2 = ST.get() in
  (**) lemma_modifies_0_1' state h0 h1 h2;

  (* Update the state with input blocks *)
  update_multi state input_blocks n;
  (**) let h3 = ST.get() in
  (**) lemma_modifies_0_1' state h0 h2 h3;

  (* Process the last block of input *)
  update_last state input_last r;
  (**) let h4 = ST.get() in
  (**) lemma_modifies_0_1' state h0 h3 h4;

  (* Finalize the hash output *)
  finish state hash;
  (**) let h5 = ST.get() in
  (**) lemma_modifies_0_1 hash h0 h4 h5;

  (* Pop the memory frame *)
  (**) pop_frame ();

  (**) let hfin = ST.get() in
  (**) modifies_popped_1 hash hinit h0 h5 hfin


*)

