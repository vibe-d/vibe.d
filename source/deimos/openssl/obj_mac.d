/* crypto/objects/obj_mac.h */

/* THIS FILE IS GENERATED FROM objects.txt by objects.pl via the
 * following command:
 * perl objects.pl objects.txt obj_mac.num obj_mac.h
 */

/* Copyright (C) 1995-1997 Eric Young (eay@cryptsoft.com)
 * All rights reserved.
 *
 * This package is an SSL implementation written
 * by Eric Young (eay@cryptsoft.com).
 * The implementation was written so as to conform with Netscapes SSL.
 *
 * This library is free for commercial and non-commercial use as long as
 * the following conditions are aheared to.  The following conditions
 * apply to all code found in this distribution, be it the RC4, RSA,
 * lhash, DES, etc., code; not just the SSL code.  The SSL documentation
 * included with this distribution is covered by the same copyright terms
 * except that the holder is Tim Hudson (tjh@cryptsoft.com).
 *
 * Copyright remains Eric Young's, and as such any Copyright notices in
 * the code are not to be removed.
 * If this package is used in a product, Eric Young should be given attribution
 * as the author of the parts of the library used.
 * This can be in the form of a textual message at program startup or
 * in documentation (online or textual) provided with the package.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the copyright
 *   notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *   must display the following acknowledgement:
 *   "This product includes cryptographic software written by
 *    Eric Young (eay@cryptsoft.com)"
 *   The word 'cryptographic' can be left out if the rouines from the library
 *   being used are not cryptographic related :-).
 * 4. If you include any Windows specific code (or a derivative thereof) from
 *   the apps directory (application code) you must include an acknowledgement:
 *   "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
 *
 * THIS SOFTWARE IS PROVIDED BY ERIC YOUNG ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * The licence and distribution terms for any publically available version or
 * derivative of this code cannot be changed.  i.e. this code cannot simply be
 * copied and put under another distribution licence
 * [including the GNU Public Licence.]
 */
module deimos.openssl.obj_mac;

enum SN_undef = "UNDEF";
enum LN_undef = "undefined";
enum NID_undef = 0;
enum OBJ_undef = "0L";

enum SN_itu_t = "ITU-T";
enum LN_itu_t = "itu-t";
enum NID_itu_t = 645;
enum OBJ_itu_t = "0L";

enum NID_ccitt = 404;
enum OBJ_ccitt = "OBJ_itu_t";

enum SN_iso = "ISO";
enum LN_iso = "iso";
enum NID_iso = 181;
enum OBJ_iso = "1L";

enum SN_joint_iso_itu_t = "JOINT-ISO-ITU-T";
enum LN_joint_iso_itu_t = "joint-iso-itu-t";
enum NID_joint_iso_itu_t = 646;
enum OBJ_joint_iso_itu_t = "2L";

enum NID_joint_iso_ccitt = 393;
enum OBJ_joint_iso_ccitt = "OBJ_joint_iso_itu_t";

enum SN_member_body = "member-body";
enum LN_member_body = "ISO Member Body";
enum NID_member_body = 182;
enum OBJ_member_body = "OBJ_iso,2L";

enum SN_identified_organization = "identified-organization";
enum NID_identified_organization = 676;
enum OBJ_identified_organization = "OBJ_iso,3L";

enum SN_hmac_md5 = "HMAC-MD5";
enum LN_hmac_md5 = "hmac-md5";
enum NID_hmac_md5 = 780;
enum OBJ_hmac_md5 = "OBJ_identified_organization,6L,1L,5L,5L,8L,1L,1L";

enum SN_hmac_sha1 = "HMAC-SHA1";
enum LN_hmac_sha1 = "hmac-sha1";
enum NID_hmac_sha1 = 781;
enum OBJ_hmac_sha1 = "OBJ_identified_organization,6L,1L,5L,5L,8L,1L,2L";

enum SN_certicom_arc = "certicom-arc";
enum NID_certicom_arc = 677;
enum OBJ_certicom_arc = "OBJ_identified_organization,132L";

enum SN_international_organizations = "international-organizations";
enum LN_international_organizations = "International Organizations";
enum NID_international_organizations = 647;
enum OBJ_international_organizations = "OBJ_joint_iso_itu_t,23L";

enum SN_wap = "wap";
enum NID_wap = 678;
enum OBJ_wap = "OBJ_international_organizations,43L";

enum SN_wap_wsg = "wap-wsg";
enum NID_wap_wsg = 679;
enum OBJ_wap_wsg = "OBJ_wap,1L";

enum SN_selected_attribute_types = "selected-attribute-types";
enum LN_selected_attribute_types = "Selected Attribute Types";
enum NID_selected_attribute_types = 394;
enum OBJ_selected_attribute_types = "OBJ_joint_iso_itu_t,5L,1L,5L";

enum SN_clearance = "clearance";
enum NID_clearance = 395;
enum OBJ_clearance = "OBJ_selected_attribute_types,55L";

enum SN_ISO_US = "ISO-US";
enum LN_ISO_US = "ISO US Member Body";
enum NID_ISO_US = 183;
enum OBJ_ISO_US = "OBJ_member_body,840L";

enum SN_X9_57 = "X9-57";
enum LN_X9_57 = "X9.57";
enum NID_X9_57 = 184;
enum OBJ_X9_57 = "OBJ_ISO_US,10040L";

enum SN_X9cm = "X9cm";
enum LN_X9cm = "X9.57 CM ?";
enum NID_X9cm = 185;
enum OBJ_X9cm = "OBJ_X9_57,4L";

enum SN_dsa = "DSA";
enum LN_dsa = "dsaEncryption";
enum NID_dsa = 116;
enum OBJ_dsa = "OBJ_X9cm,1L";

enum SN_dsaWithSHA1 = "DSA-SHA1";
enum LN_dsaWithSHA1 = "dsaWithSHA1";
enum NID_dsaWithSHA1 = 113;
enum OBJ_dsaWithSHA1 = "OBJ_X9cm,3L";

enum SN_ansi_X9_62 = "ansi-X9-62";
enum LN_ansi_X9_62 = "ANSI X9.62";
enum NID_ansi_X9_62 = 405;
enum OBJ_ansi_X9_62 = "OBJ_ISO_US,10045L";

enum OBJ_X9_62_id_fieldType = "OBJ_ansi_X9_62,1L";

enum SN_X9_62_prime_field = "prime-field";
enum NID_X9_62_prime_field = 406;
enum OBJ_X9_62_prime_field = "OBJ_X9_62_id_fieldType,1L";

enum SN_X9_62_characteristic_two_field = "characteristic-two-field";
enum NID_X9_62_characteristic_two_field = 407;
enum OBJ_X9_62_characteristic_two_field = "OBJ_X9_62_id_fieldType,2L";

enum SN_X9_62_id_characteristic_two_basis = "id-characteristic-two-basis";
enum NID_X9_62_id_characteristic_two_basis = 680;
enum OBJ_X9_62_id_characteristic_two_basis = "OBJ_X9_62_characteristic_two_field,3L";

enum SN_X9_62_onBasis = "onBasis";
enum NID_X9_62_onBasis = 681;
enum OBJ_X9_62_onBasis = "OBJ_X9_62_id_characteristic_two_basis,1L";

enum SN_X9_62_tpBasis = "tpBasis";
enum NID_X9_62_tpBasis = 682;
enum OBJ_X9_62_tpBasis = "OBJ_X9_62_id_characteristic_two_basis,2L";

enum SN_X9_62_ppBasis = "ppBasis";
enum NID_X9_62_ppBasis = 683;
enum OBJ_X9_62_ppBasis = "OBJ_X9_62_id_characteristic_two_basis,3L";

enum OBJ_X9_62_id_publicKeyType = "OBJ_ansi_X9_62,2L";

enum SN_X9_62_id_ecPublicKey = "id-ecPublicKey";
enum NID_X9_62_id_ecPublicKey = 408;
enum OBJ_X9_62_id_ecPublicKey = "OBJ_X9_62_id_publicKeyType,1L";

enum OBJ_X9_62_ellipticCurve = "OBJ_ansi_X9_62,3L";

enum OBJ_X9_62_c_TwoCurve = "OBJ_X9_62_ellipticCurve,0L";

enum SN_X9_62_c2pnb163v1 = "c2pnb163v1";
enum NID_X9_62_c2pnb163v1 = 684;
enum OBJ_X9_62_c2pnb163v1 = "OBJ_X9_62_c_TwoCurve,1L";

enum SN_X9_62_c2pnb163v2 = "c2pnb163v2";
enum NID_X9_62_c2pnb163v2 = 685;
enum OBJ_X9_62_c2pnb163v2 = "OBJ_X9_62_c_TwoCurve,2L";

enum SN_X9_62_c2pnb163v3 = "c2pnb163v3";
enum NID_X9_62_c2pnb163v3 = 686;
enum OBJ_X9_62_c2pnb163v3 = "OBJ_X9_62_c_TwoCurve,3L";

enum SN_X9_62_c2pnb176v1 = "c2pnb176v1";
enum NID_X9_62_c2pnb176v1 = 687;
enum OBJ_X9_62_c2pnb176v1 = "OBJ_X9_62_c_TwoCurve,4L";

enum SN_X9_62_c2tnb191v1 = "c2tnb191v1";
enum NID_X9_62_c2tnb191v1 = 688;
enum OBJ_X9_62_c2tnb191v1 = "OBJ_X9_62_c_TwoCurve,5L";

enum SN_X9_62_c2tnb191v2 = "c2tnb191v2";
enum NID_X9_62_c2tnb191v2 = 689;
enum OBJ_X9_62_c2tnb191v2 = "OBJ_X9_62_c_TwoCurve,6L";

enum SN_X9_62_c2tnb191v3 = "c2tnb191v3";
enum NID_X9_62_c2tnb191v3 = 690;
enum OBJ_X9_62_c2tnb191v3 = "OBJ_X9_62_c_TwoCurve,7L";

enum SN_X9_62_c2onb191v4 = "c2onb191v4";
enum NID_X9_62_c2onb191v4 = 691;
enum OBJ_X9_62_c2onb191v4 = "OBJ_X9_62_c_TwoCurve,8L";

enum SN_X9_62_c2onb191v5 = "c2onb191v5";
enum NID_X9_62_c2onb191v5 = 692;
enum OBJ_X9_62_c2onb191v5 = "OBJ_X9_62_c_TwoCurve,9L";

enum SN_X9_62_c2pnb208w1 = "c2pnb208w1";
enum NID_X9_62_c2pnb208w1 = 693;
enum OBJ_X9_62_c2pnb208w1 = "OBJ_X9_62_c_TwoCurve,10L";

enum SN_X9_62_c2tnb239v1 = "c2tnb239v1";
enum NID_X9_62_c2tnb239v1 = 694;
enum OBJ_X9_62_c2tnb239v1 = "OBJ_X9_62_c_TwoCurve,11L";

enum SN_X9_62_c2tnb239v2 = "c2tnb239v2";
enum NID_X9_62_c2tnb239v2 = 695;
enum OBJ_X9_62_c2tnb239v2 = "OBJ_X9_62_c_TwoCurve,12L";

enum SN_X9_62_c2tnb239v3 = "c2tnb239v3";
enum NID_X9_62_c2tnb239v3 = 696;
enum OBJ_X9_62_c2tnb239v3 = "OBJ_X9_62_c_TwoCurve,13L";

enum SN_X9_62_c2onb239v4 = "c2onb239v4";
enum NID_X9_62_c2onb239v4 = 697;
enum OBJ_X9_62_c2onb239v4 = "OBJ_X9_62_c_TwoCurve,14L";

enum SN_X9_62_c2onb239v5 = "c2onb239v5";
enum NID_X9_62_c2onb239v5 = 698;
enum OBJ_X9_62_c2onb239v5 = "OBJ_X9_62_c_TwoCurve,15L";

enum SN_X9_62_c2pnb272w1 = "c2pnb272w1";
enum NID_X9_62_c2pnb272w1 = 699;
enum OBJ_X9_62_c2pnb272w1 = "OBJ_X9_62_c_TwoCurve,16L";

enum SN_X9_62_c2pnb304w1 = "c2pnb304w1";
enum NID_X9_62_c2pnb304w1 = 700;
enum OBJ_X9_62_c2pnb304w1 = "OBJ_X9_62_c_TwoCurve,17L";

enum SN_X9_62_c2tnb359v1 = "c2tnb359v1";
enum NID_X9_62_c2tnb359v1 = 701;
enum OBJ_X9_62_c2tnb359v1 = "OBJ_X9_62_c_TwoCurve,18L";

enum SN_X9_62_c2pnb368w1 = "c2pnb368w1";
enum NID_X9_62_c2pnb368w1 = 702;
enum OBJ_X9_62_c2pnb368w1 = "OBJ_X9_62_c_TwoCurve,19L";

enum SN_X9_62_c2tnb431r1 = "c2tnb431r1";
enum NID_X9_62_c2tnb431r1 = 703;
enum OBJ_X9_62_c2tnb431r1 = "OBJ_X9_62_c_TwoCurve,20L";

enum OBJ_X9_62_primeCurve = "OBJ_X9_62_ellipticCurve,1L";

enum SN_X9_62_prime192v1 = "prime192v1";
enum NID_X9_62_prime192v1 = 409;
enum OBJ_X9_62_prime192v1 = "OBJ_X9_62_primeCurve,1L";

enum SN_X9_62_prime192v2 = "prime192v2";
enum NID_X9_62_prime192v2 = 410;
enum OBJ_X9_62_prime192v2 = "OBJ_X9_62_primeCurve,2L";

enum SN_X9_62_prime192v3 = "prime192v3";
enum NID_X9_62_prime192v3 = 411;
enum OBJ_X9_62_prime192v3 = "OBJ_X9_62_primeCurve,3L";

enum SN_X9_62_prime239v1 = "prime239v1";
enum NID_X9_62_prime239v1 = 412;
enum OBJ_X9_62_prime239v1 = "OBJ_X9_62_primeCurve,4L";

enum SN_X9_62_prime239v2 = "prime239v2";
enum NID_X9_62_prime239v2 = 413;
enum OBJ_X9_62_prime239v2 = "OBJ_X9_62_primeCurve,5L";

enum SN_X9_62_prime239v3 = "prime239v3";
enum NID_X9_62_prime239v3 = 414;
enum OBJ_X9_62_prime239v3 = "OBJ_X9_62_primeCurve,6L";

enum SN_X9_62_prime256v1 = "prime256v1";
enum NID_X9_62_prime256v1 = 415;
enum OBJ_X9_62_prime256v1 = "OBJ_X9_62_primeCurve,7L";

enum OBJ_X9_62_id_ecSigType = "OBJ_ansi_X9_62,4L";

enum SN_ecdsa_with_SHA1 = "ecdsa-with-SHA1";
enum NID_ecdsa_with_SHA1 = 416;
enum OBJ_ecdsa_with_SHA1 = "OBJ_X9_62_id_ecSigType,1L";

enum SN_ecdsa_with_Recommended = "ecdsa-with-Recommended";
enum NID_ecdsa_with_Recommended = 791;
enum OBJ_ecdsa_with_Recommended = "OBJ_X9_62_id_ecSigType,2L";

enum SN_ecdsa_with_Specified = "ecdsa-with-Specified";
enum NID_ecdsa_with_Specified = 792;
enum OBJ_ecdsa_with_Specified = "OBJ_X9_62_id_ecSigType,3L";

enum SN_ecdsa_with_SHA224 = "ecdsa-with-SHA224";
enum NID_ecdsa_with_SHA224 = 793;
enum OBJ_ecdsa_with_SHA224 = "OBJ_ecdsa_with_Specified,1L";

enum SN_ecdsa_with_SHA256 = "ecdsa-with-SHA256";
enum NID_ecdsa_with_SHA256 = 794;
enum OBJ_ecdsa_with_SHA256 = "OBJ_ecdsa_with_Specified,2L";

enum SN_ecdsa_with_SHA384 = "ecdsa-with-SHA384";
enum NID_ecdsa_with_SHA384 = 795;
enum OBJ_ecdsa_with_SHA384 = "OBJ_ecdsa_with_Specified,3L";

enum SN_ecdsa_with_SHA512 = "ecdsa-with-SHA512";
enum NID_ecdsa_with_SHA512 = 796;
enum OBJ_ecdsa_with_SHA512 = "OBJ_ecdsa_with_Specified,4L";

enum OBJ_secg_ellipticCurve = "OBJ_certicom_arc,0L";

enum SN_secp112r1 = "secp112r1";
enum NID_secp112r1 = 704;
enum OBJ_secp112r1 = "OBJ_secg_ellipticCurve,6L";

enum SN_secp112r2 = "secp112r2";
enum NID_secp112r2 = 705;
enum OBJ_secp112r2 = "OBJ_secg_ellipticCurve,7L";

enum SN_secp128r1 = "secp128r1";
enum NID_secp128r1 = 706;
enum OBJ_secp128r1 = "OBJ_secg_ellipticCurve,28L";

enum SN_secp128r2 = "secp128r2";
enum NID_secp128r2 = 707;
enum OBJ_secp128r2 = "OBJ_secg_ellipticCurve,29L";

enum SN_secp160k1 = "secp160k1";
enum NID_secp160k1 = 708;
enum OBJ_secp160k1 = "OBJ_secg_ellipticCurve,9L";

enum SN_secp160r1 = "secp160r1";
enum NID_secp160r1 = 709;
enum OBJ_secp160r1 = "OBJ_secg_ellipticCurve,8L";

enum SN_secp160r2 = "secp160r2";
enum NID_secp160r2 = 710;
enum OBJ_secp160r2 = "OBJ_secg_ellipticCurve,30L";

enum SN_secp192k1 = "secp192k1";
enum NID_secp192k1 = 711;
enum OBJ_secp192k1 = "OBJ_secg_ellipticCurve,31L";

enum SN_secp224k1 = "secp224k1";
enum NID_secp224k1 = 712;
enum OBJ_secp224k1 = "OBJ_secg_ellipticCurve,32L";

enum SN_secp224r1 = "secp224r1";
enum NID_secp224r1 = 713;
enum OBJ_secp224r1 = "OBJ_secg_ellipticCurve,33L";

enum SN_secp256k1 = "secp256k1";
enum NID_secp256k1 = 714;
enum OBJ_secp256k1 = "OBJ_secg_ellipticCurve,10L";

enum SN_secp384r1 = "secp384r1";
enum NID_secp384r1 = 715;
enum OBJ_secp384r1 = "OBJ_secg_ellipticCurve,34L";

enum SN_secp521r1 = "secp521r1";
enum NID_secp521r1 = 716;
enum OBJ_secp521r1 = "OBJ_secg_ellipticCurve,35L";

enum SN_sect113r1 = "sect113r1";
enum NID_sect113r1 = 717;
enum OBJ_sect113r1 = "OBJ_secg_ellipticCurve,4L";

enum SN_sect113r2 = "sect113r2";
enum NID_sect113r2 = 718;
enum OBJ_sect113r2 = "OBJ_secg_ellipticCurve,5L";

enum SN_sect131r1 = "sect131r1";
enum NID_sect131r1 = 719;
enum OBJ_sect131r1 = "OBJ_secg_ellipticCurve,22L";

enum SN_sect131r2 = "sect131r2";
enum NID_sect131r2 = 720;
enum OBJ_sect131r2 = "OBJ_secg_ellipticCurve,23L";

enum SN_sect163k1 = "sect163k1";
enum NID_sect163k1 = 721;
enum OBJ_sect163k1 = "OBJ_secg_ellipticCurve,1L";

enum SN_sect163r1 = "sect163r1";
enum NID_sect163r1 = 722;
enum OBJ_sect163r1 = "OBJ_secg_ellipticCurve,2L";

enum SN_sect163r2 = "sect163r2";
enum NID_sect163r2 = 723;
enum OBJ_sect163r2 = "OBJ_secg_ellipticCurve,15L";

enum SN_sect193r1 = "sect193r1";
enum NID_sect193r1 = 724;
enum OBJ_sect193r1 = "OBJ_secg_ellipticCurve,24L";

enum SN_sect193r2 = "sect193r2";
enum NID_sect193r2 = 725;
enum OBJ_sect193r2 = "OBJ_secg_ellipticCurve,25L";

enum SN_sect233k1 = "sect233k1";
enum NID_sect233k1 = 726;
enum OBJ_sect233k1 = "OBJ_secg_ellipticCurve,26L";

enum SN_sect233r1 = "sect233r1";
enum NID_sect233r1 = 727;
enum OBJ_sect233r1 = "OBJ_secg_ellipticCurve,27L";

enum SN_sect239k1 = "sect239k1";
enum NID_sect239k1 = 728;
enum OBJ_sect239k1 = "OBJ_secg_ellipticCurve,3L";

enum SN_sect283k1 = "sect283k1";
enum NID_sect283k1 = 729;
enum OBJ_sect283k1 = "OBJ_secg_ellipticCurve,16L";

enum SN_sect283r1 = "sect283r1";
enum NID_sect283r1 = 730;
enum OBJ_sect283r1 = "OBJ_secg_ellipticCurve,17L";

enum SN_sect409k1 = "sect409k1";
enum NID_sect409k1 = 731;
enum OBJ_sect409k1 = "OBJ_secg_ellipticCurve,36L";

enum SN_sect409r1 = "sect409r1";
enum NID_sect409r1 = 732;
enum OBJ_sect409r1 = "OBJ_secg_ellipticCurve,37L";

enum SN_sect571k1 = "sect571k1";
enum NID_sect571k1 = 733;
enum OBJ_sect571k1 = "OBJ_secg_ellipticCurve,38L";

enum SN_sect571r1 = "sect571r1";
enum NID_sect571r1 = 734;
enum OBJ_sect571r1 = "OBJ_secg_ellipticCurve,39L";

enum OBJ_wap_wsg_idm_ecid = "OBJ_wap_wsg,4L";

enum SN_wap_wsg_idm_ecid_wtls1 = "wap-wsg-idm-ecid-wtls1";
enum NID_wap_wsg_idm_ecid_wtls1 = 735;
enum OBJ_wap_wsg_idm_ecid_wtls1 = "OBJ_wap_wsg_idm_ecid,1L";

enum SN_wap_wsg_idm_ecid_wtls3 = "wap-wsg-idm-ecid-wtls3";
enum NID_wap_wsg_idm_ecid_wtls3 = 736;
enum OBJ_wap_wsg_idm_ecid_wtls3 = "OBJ_wap_wsg_idm_ecid,3L";

enum SN_wap_wsg_idm_ecid_wtls4 = "wap-wsg-idm-ecid-wtls4";
enum NID_wap_wsg_idm_ecid_wtls4 = 737;
enum OBJ_wap_wsg_idm_ecid_wtls4 = "OBJ_wap_wsg_idm_ecid,4L";

enum SN_wap_wsg_idm_ecid_wtls5 = "wap-wsg-idm-ecid-wtls5";
enum NID_wap_wsg_idm_ecid_wtls5 = 738;
enum OBJ_wap_wsg_idm_ecid_wtls5 = "OBJ_wap_wsg_idm_ecid,5L";

enum SN_wap_wsg_idm_ecid_wtls6 = "wap-wsg-idm-ecid-wtls6";
enum NID_wap_wsg_idm_ecid_wtls6 = 739;
enum OBJ_wap_wsg_idm_ecid_wtls6 = "OBJ_wap_wsg_idm_ecid,6L";

enum SN_wap_wsg_idm_ecid_wtls7 = "wap-wsg-idm-ecid-wtls7";
enum NID_wap_wsg_idm_ecid_wtls7 = 740;
enum OBJ_wap_wsg_idm_ecid_wtls7 = "OBJ_wap_wsg_idm_ecid,7L";

enum SN_wap_wsg_idm_ecid_wtls8 = "wap-wsg-idm-ecid-wtls8";
enum NID_wap_wsg_idm_ecid_wtls8 = 741;
enum OBJ_wap_wsg_idm_ecid_wtls8 = "OBJ_wap_wsg_idm_ecid,8L";

enum SN_wap_wsg_idm_ecid_wtls9 = "wap-wsg-idm-ecid-wtls9";
enum NID_wap_wsg_idm_ecid_wtls9 = 742;
enum OBJ_wap_wsg_idm_ecid_wtls9 = "OBJ_wap_wsg_idm_ecid,9L";

enum SN_wap_wsg_idm_ecid_wtls10 = "wap-wsg-idm-ecid-wtls10";
enum NID_wap_wsg_idm_ecid_wtls10 = 743;
enum OBJ_wap_wsg_idm_ecid_wtls10 = "OBJ_wap_wsg_idm_ecid,10L";

enum SN_wap_wsg_idm_ecid_wtls11 = "wap-wsg-idm-ecid-wtls11";
enum NID_wap_wsg_idm_ecid_wtls11 = 744;
enum OBJ_wap_wsg_idm_ecid_wtls11 = "OBJ_wap_wsg_idm_ecid,11L";

enum SN_wap_wsg_idm_ecid_wtls12 = "wap-wsg-idm-ecid-wtls12";
enum NID_wap_wsg_idm_ecid_wtls12 = 745;
enum OBJ_wap_wsg_idm_ecid_wtls12 = "OBJ_wap_wsg_idm_ecid,12L";

enum SN_cast5_cbc = "CAST5-CBC";
enum LN_cast5_cbc = "cast5-cbc";
enum NID_cast5_cbc = 108;
enum OBJ_cast5_cbc = "OBJ_ISO_US,113533L,7L,66L,10L";

enum SN_cast5_ecb = "CAST5-ECB";
enum LN_cast5_ecb = "cast5-ecb";
enum NID_cast5_ecb = 109;

enum SN_cast5_cfb64 = "CAST5-CFB";
enum LN_cast5_cfb64 = "cast5-cfb";
enum NID_cast5_cfb64 = 110;

enum SN_cast5_ofb64 = "CAST5-OFB";
enum LN_cast5_ofb64 = "cast5-ofb";
enum NID_cast5_ofb64 = 111;

enum LN_pbeWithMD5AndCast5_CBC = "pbeWithMD5AndCast5CBC";
enum NID_pbeWithMD5AndCast5_CBC = 112;
enum OBJ_pbeWithMD5AndCast5_CBC = "OBJ_ISO_US,113533L,7L,66L,12L";

enum SN_id_PasswordBasedMAC = "id-PasswordBasedMAC";
enum LN_id_PasswordBasedMAC = "password based MAC";
enum NID_id_PasswordBasedMAC = 782;
enum OBJ_id_PasswordBasedMAC = "OBJ_ISO_US,113533L,7L,66L,13L";

enum SN_id_DHBasedMac = "id-DHBasedMac";
enum LN_id_DHBasedMac = "Diffie-Hellman based MAC";
enum NID_id_DHBasedMac = 783;
enum OBJ_id_DHBasedMac = "OBJ_ISO_US,113533L,7L,66L,30L";

enum SN_rsadsi = "rsadsi";
enum LN_rsadsi = "RSA Data Security, Inc.";
enum NID_rsadsi = 1;
enum OBJ_rsadsi = "OBJ_ISO_US,113549L";

enum SN_pkcs = "pkcs";
enum LN_pkcs = "RSA Data Security, Inc. PKCS";
enum NID_pkcs = 2;
enum OBJ_pkcs = "OBJ_rsadsi,1L";

enum SN_pkcs1 = "pkcs1";
enum NID_pkcs1 = 186;
enum OBJ_pkcs1 = "OBJ_pkcs,1L";

enum LN_rsaEncryption = "rsaEncryption";
enum NID_rsaEncryption = 6;
enum OBJ_rsaEncryption = "OBJ_pkcs1,1L";

enum SN_md2WithRSAEncryption = "RSA-MD2";
enum LN_md2WithRSAEncryption = "md2WithRSAEncryption";
enum NID_md2WithRSAEncryption = 7;
enum OBJ_md2WithRSAEncryption = "OBJ_pkcs1,2L";

enum SN_md4WithRSAEncryption = "RSA-MD4";
enum LN_md4WithRSAEncryption = "md4WithRSAEncryption";
enum NID_md4WithRSAEncryption = 396;
enum OBJ_md4WithRSAEncryption = "OBJ_pkcs1,3L";

enum SN_md5WithRSAEncryption = "RSA-MD5";
enum LN_md5WithRSAEncryption = "md5WithRSAEncryption";
enum NID_md5WithRSAEncryption = 8;
enum OBJ_md5WithRSAEncryption = "OBJ_pkcs1,4L";

enum SN_sha1WithRSAEncryption = "RSA-SHA1";
enum LN_sha1WithRSAEncryption = "sha1WithRSAEncryption";
enum NID_sha1WithRSAEncryption = 65;
enum OBJ_sha1WithRSAEncryption = "OBJ_pkcs1,5L";

enum SN_sha256WithRSAEncryption = "RSA-SHA256";
enum LN_sha256WithRSAEncryption = "sha256WithRSAEncryption";
enum NID_sha256WithRSAEncryption = 668;
enum OBJ_sha256WithRSAEncryption = "OBJ_pkcs1,11L";

enum SN_sha384WithRSAEncryption = "RSA-SHA384";
enum LN_sha384WithRSAEncryption = "sha384WithRSAEncryption";
enum NID_sha384WithRSAEncryption = 669;
enum OBJ_sha384WithRSAEncryption = "OBJ_pkcs1,12L";

enum SN_sha512WithRSAEncryption = "RSA-SHA512";
enum LN_sha512WithRSAEncryption = "sha512WithRSAEncryption";
enum NID_sha512WithRSAEncryption = 670;
enum OBJ_sha512WithRSAEncryption = "OBJ_pkcs1,13L";

enum SN_sha224WithRSAEncryption = "RSA-SHA224";
enum LN_sha224WithRSAEncryption = "sha224WithRSAEncryption";
enum NID_sha224WithRSAEncryption = 671;
enum OBJ_sha224WithRSAEncryption = "OBJ_pkcs1,14L";

enum SN_pkcs3 = "pkcs3";
enum NID_pkcs3 = 27;
enum OBJ_pkcs3 = "OBJ_pkcs,3L";

enum LN_dhKeyAgreement = "dhKeyAgreement";
enum NID_dhKeyAgreement = 28;
enum OBJ_dhKeyAgreement = "OBJ_pkcs3,1L";

enum SN_pkcs5 = "pkcs5";
enum NID_pkcs5 = 187;
enum OBJ_pkcs5 = "OBJ_pkcs,5L";

enum SN_pbeWithMD2AndDES_CBC = "PBE-MD2-DES";
enum LN_pbeWithMD2AndDES_CBC = "pbeWithMD2AndDES-CBC";
enum NID_pbeWithMD2AndDES_CBC = 9;
enum OBJ_pbeWithMD2AndDES_CBC = "OBJ_pkcs5,1L";

enum SN_pbeWithMD5AndDES_CBC = "PBE-MD5-DES";
enum LN_pbeWithMD5AndDES_CBC = "pbeWithMD5AndDES-CBC";
enum NID_pbeWithMD5AndDES_CBC = 10;
enum OBJ_pbeWithMD5AndDES_CBC = "OBJ_pkcs5,3L";

enum SN_pbeWithMD2AndRC2_CBC = "PBE-MD2-RC2-64";
enum LN_pbeWithMD2AndRC2_CBC = "pbeWithMD2AndRC2-CBC";
enum NID_pbeWithMD2AndRC2_CBC = 168;
enum OBJ_pbeWithMD2AndRC2_CBC = "OBJ_pkcs5,4L";

enum SN_pbeWithMD5AndRC2_CBC = "PBE-MD5-RC2-64";
enum LN_pbeWithMD5AndRC2_CBC = "pbeWithMD5AndRC2-CBC";
enum NID_pbeWithMD5AndRC2_CBC = 169;
enum OBJ_pbeWithMD5AndRC2_CBC = "OBJ_pkcs5,6L";

enum SN_pbeWithSHA1AndDES_CBC = "PBE-SHA1-DES";
enum LN_pbeWithSHA1AndDES_CBC = "pbeWithSHA1AndDES-CBC";
enum NID_pbeWithSHA1AndDES_CBC = 170;
enum OBJ_pbeWithSHA1AndDES_CBC = "OBJ_pkcs5,10L";

enum SN_pbeWithSHA1AndRC2_CBC = "PBE-SHA1-RC2-64";
enum LN_pbeWithSHA1AndRC2_CBC = "pbeWithSHA1AndRC2-CBC";
enum NID_pbeWithSHA1AndRC2_CBC = 68;
enum OBJ_pbeWithSHA1AndRC2_CBC = "OBJ_pkcs5,11L";

enum LN_id_pbkdf2 = "PBKDF2";
enum NID_id_pbkdf2 = 69;
enum OBJ_id_pbkdf2 = "OBJ_pkcs5,12L";

enum LN_pbes2 = "PBES2";
enum NID_pbes2 = 161;
enum OBJ_pbes2 = "OBJ_pkcs5,13L";

enum LN_pbmac1 = "PBMAC1";
enum NID_pbmac1 = 162;
enum OBJ_pbmac1 = "OBJ_pkcs5,14L";

enum SN_pkcs7 = "pkcs7";
enum NID_pkcs7 = 20;
enum OBJ_pkcs7 = "OBJ_pkcs,7L";

enum LN_pkcs7_data = "pkcs7-data";
enum NID_pkcs7_data = 21;
enum OBJ_pkcs7_data = "OBJ_pkcs7,1L";

enum LN_pkcs7_signed = "pkcs7-signedData";
enum NID_pkcs7_signed = 22;
enum OBJ_pkcs7_signed = "OBJ_pkcs7,2L";

enum LN_pkcs7_enveloped = "pkcs7-envelopedData";
enum NID_pkcs7_enveloped = 23;
enum OBJ_pkcs7_enveloped = "OBJ_pkcs7,3L";

enum LN_pkcs7_signedAndEnveloped = "pkcs7-signedAndEnvelopedData";
enum NID_pkcs7_signedAndEnveloped = 24;
enum OBJ_pkcs7_signedAndEnveloped = "OBJ_pkcs7,4L";

enum LN_pkcs7_digest = "pkcs7-digestData";
enum NID_pkcs7_digest = 25;
enum OBJ_pkcs7_digest = "OBJ_pkcs7,5L";

enum LN_pkcs7_encrypted = "pkcs7-encryptedData";
enum NID_pkcs7_encrypted = 26;
enum OBJ_pkcs7_encrypted = "OBJ_pkcs7,6L";

enum SN_pkcs9 = "pkcs9";
enum NID_pkcs9 = 47;
enum OBJ_pkcs9 = "OBJ_pkcs,9L";

enum LN_pkcs9_emailAddress = "emailAddress";
enum NID_pkcs9_emailAddress = 48;
enum OBJ_pkcs9_emailAddress = "OBJ_pkcs9,1L";

enum LN_pkcs9_unstructuredName = "unstructuredName";
enum NID_pkcs9_unstructuredName = 49;
enum OBJ_pkcs9_unstructuredName = "OBJ_pkcs9,2L";

enum LN_pkcs9_contentType = "contentType";
enum NID_pkcs9_contentType = 50;
enum OBJ_pkcs9_contentType = "OBJ_pkcs9,3L";

enum LN_pkcs9_messageDigest = "messageDigest";
enum NID_pkcs9_messageDigest = 51;
enum OBJ_pkcs9_messageDigest = "OBJ_pkcs9,4L";

enum LN_pkcs9_signingTime = "signingTime";
enum NID_pkcs9_signingTime = 52;
enum OBJ_pkcs9_signingTime = "OBJ_pkcs9,5L";

enum LN_pkcs9_countersignature = "countersignature";
enum NID_pkcs9_countersignature = 53;
enum OBJ_pkcs9_countersignature = "OBJ_pkcs9,6L";

enum LN_pkcs9_challengePassword = "challengePassword";
enum NID_pkcs9_challengePassword = 54;
enum OBJ_pkcs9_challengePassword = "OBJ_pkcs9,7L";

enum LN_pkcs9_unstructuredAddress = "unstructuredAddress";
enum NID_pkcs9_unstructuredAddress = 55;
enum OBJ_pkcs9_unstructuredAddress = "OBJ_pkcs9,8L";

enum LN_pkcs9_extCertAttributes = "extendedCertificateAttributes";
enum NID_pkcs9_extCertAttributes = 56;
enum OBJ_pkcs9_extCertAttributes = "OBJ_pkcs9,9L";

enum SN_ext_req = "extReq";
enum LN_ext_req = "Extension Request";
enum NID_ext_req = 172;
enum OBJ_ext_req = "OBJ_pkcs9,14L";

enum SN_SMIMECapabilities = "SMIME-CAPS";
enum LN_SMIMECapabilities = "S/MIME Capabilities";
enum NID_SMIMECapabilities = 167;
enum OBJ_SMIMECapabilities = "OBJ_pkcs9,15L";

enum SN_SMIME = "SMIME";
enum LN_SMIME = "S/MIME";
enum NID_SMIME = 188;
enum OBJ_SMIME = "OBJ_pkcs9,16L";

enum SN_id_smime_mod = "id-smime-mod";
enum NID_id_smime_mod = 189;
enum OBJ_id_smime_mod = "OBJ_SMIME,0L";

enum SN_id_smime_ct = "id-smime-ct";
enum NID_id_smime_ct = 190;
enum OBJ_id_smime_ct = "OBJ_SMIME,1L";

enum SN_id_smime_aa = "id-smime-aa";
enum NID_id_smime_aa = 191;
enum OBJ_id_smime_aa = "OBJ_SMIME,2L";

enum SN_id_smime_alg = "id-smime-alg";
enum NID_id_smime_alg = 192;
enum OBJ_id_smime_alg = "OBJ_SMIME,3L";

enum SN_id_smime_cd = "id-smime-cd";
enum NID_id_smime_cd = 193;
enum OBJ_id_smime_cd = "OBJ_SMIME,4L";

enum SN_id_smime_spq = "id-smime-spq";
enum NID_id_smime_spq = 194;
enum OBJ_id_smime_spq = "OBJ_SMIME,5L";

enum SN_id_smime_cti = "id-smime-cti";
enum NID_id_smime_cti = 195;
enum OBJ_id_smime_cti = "OBJ_SMIME,6L";

enum SN_id_smime_mod_cms = "id-smime-mod-cms";
enum NID_id_smime_mod_cms = 196;
enum OBJ_id_smime_mod_cms = "OBJ_id_smime_mod,1L";

enum SN_id_smime_mod_ess = "id-smime-mod-ess";
enum NID_id_smime_mod_ess = 197;
enum OBJ_id_smime_mod_ess = "OBJ_id_smime_mod,2L";

enum SN_id_smime_mod_oid = "id-smime-mod-oid";
enum NID_id_smime_mod_oid = 198;
enum OBJ_id_smime_mod_oid = "OBJ_id_smime_mod,3L";

enum SN_id_smime_mod_msg_v3 = "id-smime-mod-msg-v3";
enum NID_id_smime_mod_msg_v3 = 199;
enum OBJ_id_smime_mod_msg_v3 = "OBJ_id_smime_mod,4L";

enum SN_id_smime_mod_ets_eSignature_88 = "id-smime-mod-ets-eSignature-88";
enum NID_id_smime_mod_ets_eSignature_88 = 200;
enum OBJ_id_smime_mod_ets_eSignature_88 = "OBJ_id_smime_mod,5L";

enum SN_id_smime_mod_ets_eSignature_97 = "id-smime-mod-ets-eSignature-97";
enum NID_id_smime_mod_ets_eSignature_97 = 201;
enum OBJ_id_smime_mod_ets_eSignature_97 = "OBJ_id_smime_mod,6L";

enum SN_id_smime_mod_ets_eSigPolicy_88 = "id-smime-mod-ets-eSigPolicy-88";
enum NID_id_smime_mod_ets_eSigPolicy_88 = 202;
enum OBJ_id_smime_mod_ets_eSigPolicy_88 = "OBJ_id_smime_mod,7L";

enum SN_id_smime_mod_ets_eSigPolicy_97 = "id-smime-mod-ets-eSigPolicy-97";
enum NID_id_smime_mod_ets_eSigPolicy_97 = 203;
enum OBJ_id_smime_mod_ets_eSigPolicy_97 = "OBJ_id_smime_mod,8L";

enum SN_id_smime_ct_receipt = "id-smime-ct-receipt";
enum NID_id_smime_ct_receipt = 204;
enum OBJ_id_smime_ct_receipt = "OBJ_id_smime_ct,1L";

enum SN_id_smime_ct_authData = "id-smime-ct-authData";
enum NID_id_smime_ct_authData = 205;
enum OBJ_id_smime_ct_authData = "OBJ_id_smime_ct,2L";

enum SN_id_smime_ct_publishCert = "id-smime-ct-publishCert";
enum NID_id_smime_ct_publishCert = 206;
enum OBJ_id_smime_ct_publishCert = "OBJ_id_smime_ct,3L";

enum SN_id_smime_ct_TSTInfo = "id-smime-ct-TSTInfo";
enum NID_id_smime_ct_TSTInfo = 207;
enum OBJ_id_smime_ct_TSTInfo = "OBJ_id_smime_ct,4L";

enum SN_id_smime_ct_TDTInfo = "id-smime-ct-TDTInfo";
enum NID_id_smime_ct_TDTInfo = 208;
enum OBJ_id_smime_ct_TDTInfo = "OBJ_id_smime_ct,5L";

enum SN_id_smime_ct_contentInfo = "id-smime-ct-contentInfo";
enum NID_id_smime_ct_contentInfo = 209;
enum OBJ_id_smime_ct_contentInfo = "OBJ_id_smime_ct,6L";

enum SN_id_smime_ct_DVCSRequestData = "id-smime-ct-DVCSRequestData";
enum NID_id_smime_ct_DVCSRequestData = 210;
enum OBJ_id_smime_ct_DVCSRequestData = "OBJ_id_smime_ct,7L";

enum SN_id_smime_ct_DVCSResponseData = "id-smime-ct-DVCSResponseData";
enum NID_id_smime_ct_DVCSResponseData = 211;
enum OBJ_id_smime_ct_DVCSResponseData = "OBJ_id_smime_ct,8L";

enum SN_id_smime_ct_compressedData = "id-smime-ct-compressedData";
enum NID_id_smime_ct_compressedData = 786;
enum OBJ_id_smime_ct_compressedData = "OBJ_id_smime_ct,9L";

enum SN_id_ct_asciiTextWithCRLF = "id-ct-asciiTextWithCRLF";
enum NID_id_ct_asciiTextWithCRLF = 787;
enum OBJ_id_ct_asciiTextWithCRLF = "OBJ_id_smime_ct,27L";

enum SN_id_smime_aa_receiptRequest = "id-smime-aa-receiptRequest";
enum NID_id_smime_aa_receiptRequest = 212;
enum OBJ_id_smime_aa_receiptRequest = "OBJ_id_smime_aa,1L";

enum SN_id_smime_aa_securityLabel = "id-smime-aa-securityLabel";
enum NID_id_smime_aa_securityLabel = 213;
enum OBJ_id_smime_aa_securityLabel = "OBJ_id_smime_aa,2L";

enum SN_id_smime_aa_mlExpandHistory = "id-smime-aa-mlExpandHistory";
enum NID_id_smime_aa_mlExpandHistory = 214;
enum OBJ_id_smime_aa_mlExpandHistory = "OBJ_id_smime_aa,3L";

enum SN_id_smime_aa_contentHint = "id-smime-aa-contentHint";
enum NID_id_smime_aa_contentHint = 215;
enum OBJ_id_smime_aa_contentHint = "OBJ_id_smime_aa,4L";

enum SN_id_smime_aa_msgSigDigest = "id-smime-aa-msgSigDigest";
enum NID_id_smime_aa_msgSigDigest = 216;
enum OBJ_id_smime_aa_msgSigDigest = "OBJ_id_smime_aa,5L";

enum SN_id_smime_aa_encapContentType = "id-smime-aa-encapContentType";
enum NID_id_smime_aa_encapContentType = 217;
enum OBJ_id_smime_aa_encapContentType = "OBJ_id_smime_aa,6L";

enum SN_id_smime_aa_contentIdentifier = "id-smime-aa-contentIdentifier";
enum NID_id_smime_aa_contentIdentifier = 218;
enum OBJ_id_smime_aa_contentIdentifier = "OBJ_id_smime_aa,7L";

enum SN_id_smime_aa_macValue = "id-smime-aa-macValue";
enum NID_id_smime_aa_macValue = 219;
enum OBJ_id_smime_aa_macValue = "OBJ_id_smime_aa,8L";

enum SN_id_smime_aa_equivalentLabels = "id-smime-aa-equivalentLabels";
enum NID_id_smime_aa_equivalentLabels = 220;
enum OBJ_id_smime_aa_equivalentLabels = "OBJ_id_smime_aa,9L";

enum SN_id_smime_aa_contentReference = "id-smime-aa-contentReference";
enum NID_id_smime_aa_contentReference = 221;
enum OBJ_id_smime_aa_contentReference = "OBJ_id_smime_aa,10L";

enum SN_id_smime_aa_encrypKeyPref = "id-smime-aa-encrypKeyPref";
enum NID_id_smime_aa_encrypKeyPref = 222;
enum OBJ_id_smime_aa_encrypKeyPref = "OBJ_id_smime_aa,11L";

enum SN_id_smime_aa_signingCertificate = "id-smime-aa-signingCertificate";
enum NID_id_smime_aa_signingCertificate = 223;
enum OBJ_id_smime_aa_signingCertificate = "OBJ_id_smime_aa,12L";

enum SN_id_smime_aa_smimeEncryptCerts = "id-smime-aa-smimeEncryptCerts";
enum NID_id_smime_aa_smimeEncryptCerts = 224;
enum OBJ_id_smime_aa_smimeEncryptCerts = "OBJ_id_smime_aa,13L";

enum SN_id_smime_aa_timeStampToken = "id-smime-aa-timeStampToken";
enum NID_id_smime_aa_timeStampToken = 225;
enum OBJ_id_smime_aa_timeStampToken = "OBJ_id_smime_aa,14L";

enum SN_id_smime_aa_ets_sigPolicyId = "id-smime-aa-ets-sigPolicyId";
enum NID_id_smime_aa_ets_sigPolicyId = 226;
enum OBJ_id_smime_aa_ets_sigPolicyId = "OBJ_id_smime_aa,15L";

enum SN_id_smime_aa_ets_commitmentType = "id-smime-aa-ets-commitmentType";
enum NID_id_smime_aa_ets_commitmentType = 227;
enum OBJ_id_smime_aa_ets_commitmentType = "OBJ_id_smime_aa,16L";

enum SN_id_smime_aa_ets_signerLocation = "id-smime-aa-ets-signerLocation";
enum NID_id_smime_aa_ets_signerLocation = 228;
enum OBJ_id_smime_aa_ets_signerLocation = "OBJ_id_smime_aa,17L";

enum SN_id_smime_aa_ets_signerAttr = "id-smime-aa-ets-signerAttr";
enum NID_id_smime_aa_ets_signerAttr = 229;
enum OBJ_id_smime_aa_ets_signerAttr = "OBJ_id_smime_aa,18L";

enum SN_id_smime_aa_ets_otherSigCert = "id-smime-aa-ets-otherSigCert";
enum NID_id_smime_aa_ets_otherSigCert = 230;
enum OBJ_id_smime_aa_ets_otherSigCert = "OBJ_id_smime_aa,19L";

enum SN_id_smime_aa_ets_contentTimestamp = "id-smime-aa-ets-contentTimestamp";
enum NID_id_smime_aa_ets_contentTimestamp = 231;
enum OBJ_id_smime_aa_ets_contentTimestamp = "OBJ_id_smime_aa,20L";

enum SN_id_smime_aa_ets_CertificateRefs = "id-smime-aa-ets-CertificateRefs";
enum NID_id_smime_aa_ets_CertificateRefs = 232;
enum OBJ_id_smime_aa_ets_CertificateRefs = "OBJ_id_smime_aa,21L";

enum SN_id_smime_aa_ets_RevocationRefs = "id-smime-aa-ets-RevocationRefs";
enum NID_id_smime_aa_ets_RevocationRefs = 233;
enum OBJ_id_smime_aa_ets_RevocationRefs = "OBJ_id_smime_aa,22L";

enum SN_id_smime_aa_ets_certValues = "id-smime-aa-ets-certValues";
enum NID_id_smime_aa_ets_certValues = 234;
enum OBJ_id_smime_aa_ets_certValues = "OBJ_id_smime_aa,23L";

enum SN_id_smime_aa_ets_revocationValues = "id-smime-aa-ets-revocationValues";
enum NID_id_smime_aa_ets_revocationValues = 235;
enum OBJ_id_smime_aa_ets_revocationValues = "OBJ_id_smime_aa,24L";

enum SN_id_smime_aa_ets_escTimeStamp = "id-smime-aa-ets-escTimeStamp";
enum NID_id_smime_aa_ets_escTimeStamp = 236;
enum OBJ_id_smime_aa_ets_escTimeStamp = "OBJ_id_smime_aa,25L";

enum SN_id_smime_aa_ets_certCRLTimestamp = "id-smime-aa-ets-certCRLTimestamp";
enum NID_id_smime_aa_ets_certCRLTimestamp = 237;
enum OBJ_id_smime_aa_ets_certCRLTimestamp = "OBJ_id_smime_aa,26L";

enum SN_id_smime_aa_ets_archiveTimeStamp = "id-smime-aa-ets-archiveTimeStamp";
enum NID_id_smime_aa_ets_archiveTimeStamp = 238;
enum OBJ_id_smime_aa_ets_archiveTimeStamp = "OBJ_id_smime_aa,27L";

enum SN_id_smime_aa_signatureType = "id-smime-aa-signatureType";
enum NID_id_smime_aa_signatureType = 239;
enum OBJ_id_smime_aa_signatureType = "OBJ_id_smime_aa,28L";

enum SN_id_smime_aa_dvcs_dvc = "id-smime-aa-dvcs-dvc";
enum NID_id_smime_aa_dvcs_dvc = 240;
enum OBJ_id_smime_aa_dvcs_dvc = "OBJ_id_smime_aa,29L";

enum SN_id_smime_alg_ESDHwith3DES = "id-smime-alg-ESDHwith3DES";
enum NID_id_smime_alg_ESDHwith3DES = 241;
enum OBJ_id_smime_alg_ESDHwith3DES = "OBJ_id_smime_alg,1L";

enum SN_id_smime_alg_ESDHwithRC2 = "id-smime-alg-ESDHwithRC2";
enum NID_id_smime_alg_ESDHwithRC2 = 242;
enum OBJ_id_smime_alg_ESDHwithRC2 = "OBJ_id_smime_alg,2L";

enum SN_id_smime_alg_3DESwrap = "id-smime-alg-3DESwrap";
enum NID_id_smime_alg_3DESwrap = 243;
enum OBJ_id_smime_alg_3DESwrap = "OBJ_id_smime_alg,3L";

enum SN_id_smime_alg_RC2wrap = "id-smime-alg-RC2wrap";
enum NID_id_smime_alg_RC2wrap = 244;
enum OBJ_id_smime_alg_RC2wrap = "OBJ_id_smime_alg,4L";

enum SN_id_smime_alg_ESDH = "id-smime-alg-ESDH";
enum NID_id_smime_alg_ESDH = 245;
enum OBJ_id_smime_alg_ESDH = "OBJ_id_smime_alg,5L";

enum SN_id_smime_alg_CMS3DESwrap = "id-smime-alg-CMS3DESwrap";
enum NID_id_smime_alg_CMS3DESwrap = 246;
enum OBJ_id_smime_alg_CMS3DESwrap = "OBJ_id_smime_alg,6L";

enum SN_id_smime_alg_CMSRC2wrap = "id-smime-alg-CMSRC2wrap";
enum NID_id_smime_alg_CMSRC2wrap = 247;
enum OBJ_id_smime_alg_CMSRC2wrap = "OBJ_id_smime_alg,7L";

enum SN_id_smime_cd_ldap = "id-smime-cd-ldap";
enum NID_id_smime_cd_ldap = 248;
enum OBJ_id_smime_cd_ldap = "OBJ_id_smime_cd,1L";

enum SN_id_smime_spq_ets_sqt_uri = "id-smime-spq-ets-sqt-uri";
enum NID_id_smime_spq_ets_sqt_uri = 249;
enum OBJ_id_smime_spq_ets_sqt_uri = "OBJ_id_smime_spq,1L";

enum SN_id_smime_spq_ets_sqt_unotice = "id-smime-spq-ets-sqt-unotice";
enum NID_id_smime_spq_ets_sqt_unotice = 250;
enum OBJ_id_smime_spq_ets_sqt_unotice = "OBJ_id_smime_spq,2L";

enum SN_id_smime_cti_ets_proofOfOrigin = "id-smime-cti-ets-proofOfOrigin";
enum NID_id_smime_cti_ets_proofOfOrigin = 251;
enum OBJ_id_smime_cti_ets_proofOfOrigin = "OBJ_id_smime_cti,1L";

enum SN_id_smime_cti_ets_proofOfReceipt = "id-smime-cti-ets-proofOfReceipt";
enum NID_id_smime_cti_ets_proofOfReceipt = 252;
enum OBJ_id_smime_cti_ets_proofOfReceipt = "OBJ_id_smime_cti,2L";

enum SN_id_smime_cti_ets_proofOfDelivery = "id-smime-cti-ets-proofOfDelivery";
enum NID_id_smime_cti_ets_proofOfDelivery = 253;
enum OBJ_id_smime_cti_ets_proofOfDelivery = "OBJ_id_smime_cti,3L";

enum SN_id_smime_cti_ets_proofOfSender = "id-smime-cti-ets-proofOfSender";
enum NID_id_smime_cti_ets_proofOfSender = 254;
enum OBJ_id_smime_cti_ets_proofOfSender = "OBJ_id_smime_cti,4L";

enum SN_id_smime_cti_ets_proofOfApproval = "id-smime-cti-ets-proofOfApproval";
enum NID_id_smime_cti_ets_proofOfApproval = 255;
enum OBJ_id_smime_cti_ets_proofOfApproval = "OBJ_id_smime_cti,5L";

enum SN_id_smime_cti_ets_proofOfCreation = "id-smime-cti-ets-proofOfCreation";
enum NID_id_smime_cti_ets_proofOfCreation = 256;
enum OBJ_id_smime_cti_ets_proofOfCreation = "OBJ_id_smime_cti,6L";

enum LN_friendlyName = "friendlyName";
enum NID_friendlyName = 156;
enum OBJ_friendlyName = "OBJ_pkcs9,20L";

enum LN_localKeyID = "localKeyID";
enum NID_localKeyID = 157;
enum OBJ_localKeyID = "OBJ_pkcs9,21L";

enum SN_ms_csp_name = "CSPName";
enum LN_ms_csp_name = "Microsoft CSP Name";
enum NID_ms_csp_name = 417;
enum OBJ_ms_csp_name = "1L,3L,6L,1L,4L,1L,311L,17L,1L";

enum SN_LocalKeySet = "LocalKeySet";
enum LN_LocalKeySet = "Microsoft Local Key set";
enum NID_LocalKeySet = 856;
enum OBJ_LocalKeySet = "1L,3L,6L,1L,4L,1L,311L,17L,2L";

enum OBJ_certTypes = "OBJ_pkcs9,22L";

enum LN_x509Certificate = "x509Certificate";
enum NID_x509Certificate = 158;
enum OBJ_x509Certificate = "OBJ_certTypes,1L";

enum LN_sdsiCertificate = "sdsiCertificate";
enum NID_sdsiCertificate = 159;
enum OBJ_sdsiCertificate = "OBJ_certTypes,2L";

enum OBJ_crlTypes = "OBJ_pkcs9,23L";

enum LN_x509Crl = "x509Crl";
enum NID_x509Crl = 160;
enum OBJ_x509Crl = "OBJ_crlTypes,1L";

enum OBJ_pkcs12 = "OBJ_pkcs,12L";

enum OBJ_pkcs12_pbeids = "OBJ_pkcs12,1L";

enum SN_pbe_WithSHA1And128BitRC4 = "PBE-SHA1-RC4-128";
enum LN_pbe_WithSHA1And128BitRC4 = "pbeWithSHA1And128BitRC4";
enum NID_pbe_WithSHA1And128BitRC4 = 144;
enum OBJ_pbe_WithSHA1And128BitRC4 = "OBJ_pkcs12_pbeids,1L";

enum SN_pbe_WithSHA1And40BitRC4 = "PBE-SHA1-RC4-40";
enum LN_pbe_WithSHA1And40BitRC4 = "pbeWithSHA1And40BitRC4";
enum NID_pbe_WithSHA1And40BitRC4 = 145;
enum OBJ_pbe_WithSHA1And40BitRC4 = "OBJ_pkcs12_pbeids,2L";

enum SN_pbe_WithSHA1And3_Key_TripleDES_CBC = "PBE-SHA1-3DES";
enum LN_pbe_WithSHA1And3_Key_TripleDES_CBC = "pbeWithSHA1And3-KeyTripleDES-CBC";
enum NID_pbe_WithSHA1And3_Key_TripleDES_CBC = 146;
enum OBJ_pbe_WithSHA1And3_Key_TripleDES_CBC = "OBJ_pkcs12_pbeids,3L";

enum SN_pbe_WithSHA1And2_Key_TripleDES_CBC = "PBE-SHA1-2DES";
enum LN_pbe_WithSHA1And2_Key_TripleDES_CBC = "pbeWithSHA1And2-KeyTripleDES-CBC";
enum NID_pbe_WithSHA1And2_Key_TripleDES_CBC = 147;
enum OBJ_pbe_WithSHA1And2_Key_TripleDES_CBC = "OBJ_pkcs12_pbeids,4L";

enum SN_pbe_WithSHA1And128BitRC2_CBC = "PBE-SHA1-RC2-128";
enum LN_pbe_WithSHA1And128BitRC2_CBC = "pbeWithSHA1And128BitRC2-CBC";
enum NID_pbe_WithSHA1And128BitRC2_CBC = 148;
enum OBJ_pbe_WithSHA1And128BitRC2_CBC = "OBJ_pkcs12_pbeids,5L";

enum SN_pbe_WithSHA1And40BitRC2_CBC = "PBE-SHA1-RC2-40";
enum LN_pbe_WithSHA1And40BitRC2_CBC = "pbeWithSHA1And40BitRC2-CBC";
enum NID_pbe_WithSHA1And40BitRC2_CBC = 149;
enum OBJ_pbe_WithSHA1And40BitRC2_CBC = "OBJ_pkcs12_pbeids,6L";

enum OBJ_pkcs12_Version1 = "OBJ_pkcs12,10L";

enum OBJ_pkcs12_BagIds = "OBJ_pkcs12_Version1,1L";

enum LN_keyBag = "keyBag";
enum NID_keyBag = 150;
enum OBJ_keyBag = "OBJ_pkcs12_BagIds,1L";

enum LN_pkcs8ShroudedKeyBag = "pkcs8ShroudedKeyBag";
enum NID_pkcs8ShroudedKeyBag = 151;
enum OBJ_pkcs8ShroudedKeyBag = "OBJ_pkcs12_BagIds,2L";

enum LN_certBag = "certBag";
enum NID_certBag = 152;
enum OBJ_certBag = "OBJ_pkcs12_BagIds,3L";

enum LN_crlBag = "crlBag";
enum NID_crlBag = 153;
enum OBJ_crlBag = "OBJ_pkcs12_BagIds,4L";

enum LN_secretBag = "secretBag";
enum NID_secretBag = 154;
enum OBJ_secretBag = "OBJ_pkcs12_BagIds,5L";

enum LN_safeContentsBag = "safeContentsBag";
enum NID_safeContentsBag = 155;
enum OBJ_safeContentsBag = "OBJ_pkcs12_BagIds,6L";

enum SN_md2 = "MD2";
enum LN_md2 = "md2";
enum NID_md2 = 3;
enum OBJ_md2 = "OBJ_rsadsi,2L,2L";

enum SN_md4 = "MD4";
enum LN_md4 = "md4";
enum NID_md4 = 257;
enum OBJ_md4 = "OBJ_rsadsi,2L,4L";

enum SN_md5 = "MD5";
enum LN_md5 = "md5";
enum NID_md5 = 4;
enum OBJ_md5 = "OBJ_rsadsi,2L,5L";

enum SN_md5_sha1 = "MD5-SHA1";
enum LN_md5_sha1 = "md5-sha1";
enum NID_md5_sha1 = 114;

enum LN_hmacWithMD5 = "hmacWithMD5";
enum NID_hmacWithMD5 = 797;
enum OBJ_hmacWithMD5 = "OBJ_rsadsi,2L,6L";

enum LN_hmacWithSHA1 = "hmacWithSHA1";
enum NID_hmacWithSHA1 = 163;
enum OBJ_hmacWithSHA1 = "OBJ_rsadsi,2L,7L";

enum LN_hmacWithSHA224 = "hmacWithSHA224";
enum NID_hmacWithSHA224 = 798;
enum OBJ_hmacWithSHA224 = "OBJ_rsadsi,2L,8L";

enum LN_hmacWithSHA256 = "hmacWithSHA256";
enum NID_hmacWithSHA256 = 799;
enum OBJ_hmacWithSHA256 = "OBJ_rsadsi,2L,9L";

enum LN_hmacWithSHA384 = "hmacWithSHA384";
enum NID_hmacWithSHA384 = 800;
enum OBJ_hmacWithSHA384 = "OBJ_rsadsi,2L,10L";

enum LN_hmacWithSHA512 = "hmacWithSHA512";
enum NID_hmacWithSHA512 = 801;
enum OBJ_hmacWithSHA512 = "OBJ_rsadsi,2L,11L";

enum SN_rc2_cbc = "RC2-CBC";
enum LN_rc2_cbc = "rc2-cbc";
enum NID_rc2_cbc = 37;
enum OBJ_rc2_cbc = "OBJ_rsadsi,3L,2L";

enum SN_rc2_ecb = "RC2-ECB";
enum LN_rc2_ecb = "rc2-ecb";
enum NID_rc2_ecb = 38;

enum SN_rc2_cfb64 = "RC2-CFB";
enum LN_rc2_cfb64 = "rc2-cfb";
enum NID_rc2_cfb64 = 39;

enum SN_rc2_ofb64 = "RC2-OFB";
enum LN_rc2_ofb64 = "rc2-ofb";
enum NID_rc2_ofb64 = 40;

enum SN_rc2_40_cbc = "RC2-40-CBC";
enum LN_rc2_40_cbc = "rc2-40-cbc";
enum NID_rc2_40_cbc = 98;

enum SN_rc2_64_cbc = "RC2-64-CBC";
enum LN_rc2_64_cbc = "rc2-64-cbc";
enum NID_rc2_64_cbc = 166;

enum SN_rc4 = "RC4";
enum LN_rc4 = "rc4";
enum NID_rc4 = 5;
enum OBJ_rc4 = "OBJ_rsadsi,3L,4L";

enum SN_rc4_40 = "RC4-40";
enum LN_rc4_40 = "rc4-40";
enum NID_rc4_40 = 97;

enum SN_des_ede3_cbc = "DES-EDE3-CBC";
enum LN_des_ede3_cbc = "des-ede3-cbc";
enum NID_des_ede3_cbc = 44;
enum OBJ_des_ede3_cbc = "OBJ_rsadsi,3L,7L";

enum SN_rc5_cbc = "RC5-CBC";
enum LN_rc5_cbc = "rc5-cbc";
enum NID_rc5_cbc = 120;
enum OBJ_rc5_cbc = "OBJ_rsadsi,3L,8L";

enum SN_rc5_ecb = "RC5-ECB";
enum LN_rc5_ecb = "rc5-ecb";
enum NID_rc5_ecb = 121;

enum SN_rc5_cfb64 = "RC5-CFB";
enum LN_rc5_cfb64 = "rc5-cfb";
enum NID_rc5_cfb64 = 122;

enum SN_rc5_ofb64 = "RC5-OFB";
enum LN_rc5_ofb64 = "rc5-ofb";
enum NID_rc5_ofb64 = 123;

enum SN_ms_ext_req = "msExtReq";
enum LN_ms_ext_req = "Microsoft Extension Request";
enum NID_ms_ext_req = 171;
enum OBJ_ms_ext_req = "1L,3L,6L,1L,4L,1L,311L,2L,1L,14L";

enum SN_ms_code_ind = "msCodeInd";
enum LN_ms_code_ind = "Microsoft Individual Code Signing";
enum NID_ms_code_ind = 134;
enum OBJ_ms_code_ind = "1L,3L,6L,1L,4L,1L,311L,2L,1L,21L";

enum SN_ms_code_com = "msCodeCom";
enum LN_ms_code_com = "Microsoft Commercial Code Signing";
enum NID_ms_code_com = 135;
enum OBJ_ms_code_com = "1L,3L,6L,1L,4L,1L,311L,2L,1L,22L";

enum SN_ms_ctl_sign = "msCTLSign";
enum LN_ms_ctl_sign = "Microsoft Trust List Signing";
enum NID_ms_ctl_sign = 136;
enum OBJ_ms_ctl_sign = "1L,3L,6L,1L,4L,1L,311L,10L,3L,1L";

enum SN_ms_sgc = "msSGC";
enum LN_ms_sgc = "Microsoft Server Gated Crypto";
enum NID_ms_sgc = 137;
enum OBJ_ms_sgc = "1L,3L,6L,1L,4L,1L,311L,10L,3L,3L";

enum SN_ms_efs = "msEFS";
enum LN_ms_efs = "Microsoft Encrypted File System";
enum NID_ms_efs = 138;
enum OBJ_ms_efs = "1L,3L,6L,1L,4L,1L,311L,10L,3L,4L";

enum SN_ms_smartcard_login = "msSmartcardLogin";
enum LN_ms_smartcard_login = "Microsoft Smartcardlogin";
enum NID_ms_smartcard_login = 648;
enum OBJ_ms_smartcard_login = "1L,3L,6L,1L,4L,1L,311L,20L,2L,2L";

enum SN_ms_upn = "msUPN";
enum LN_ms_upn = "Microsoft Universal Principal Name";
enum NID_ms_upn = 649;
enum OBJ_ms_upn = "1L,3L,6L,1L,4L,1L,311L,20L,2L,3L";

enum SN_idea_cbc = "IDEA-CBC";
enum LN_idea_cbc = "idea-cbc";
enum NID_idea_cbc = 34;
enum OBJ_idea_cbc = "1L,3L,6L,1L,4L,1L,188L,7L,1L,1L,2L";

enum SN_idea_ecb = "IDEA-ECB";
enum LN_idea_ecb = "idea-ecb";
enum NID_idea_ecb = 36;

enum SN_idea_cfb64 = "IDEA-CFB";
enum LN_idea_cfb64 = "idea-cfb";
enum NID_idea_cfb64 = 35;

enum SN_idea_ofb64 = "IDEA-OFB";
enum LN_idea_ofb64 = "idea-ofb";
enum NID_idea_ofb64 = 46;

enum SN_bf_cbc = "BF-CBC";
enum LN_bf_cbc = "bf-cbc";
enum NID_bf_cbc = 91;
enum OBJ_bf_cbc = "1L,3L,6L,1L,4L,1L,3029L,1L,2L";

enum SN_bf_ecb = "BF-ECB";
enum LN_bf_ecb = "bf-ecb";
enum NID_bf_ecb = 92;

enum SN_bf_cfb64 = "BF-CFB";
enum LN_bf_cfb64 = "bf-cfb";
enum NID_bf_cfb64 = 93;

enum SN_bf_ofb64 = "BF-OFB";
enum LN_bf_ofb64 = "bf-ofb";
enum NID_bf_ofb64 = 94;

enum SN_id_pkix = "PKIX";
enum NID_id_pkix = 127;
enum OBJ_id_pkix = "1L,3L,6L,1L,5L,5L,7L";

enum SN_id_pkix_mod = "id-pkix-mod";
enum NID_id_pkix_mod = 258;
enum OBJ_id_pkix_mod = "OBJ_id_pkix,0L";

enum SN_id_pe = "id-pe";
enum NID_id_pe = 175;
enum OBJ_id_pe = "OBJ_id_pkix,1L";

enum SN_id_qt = "id-qt";
enum NID_id_qt = 259;
enum OBJ_id_qt = "OBJ_id_pkix,2L";

enum SN_id_kp = "id-kp";
enum NID_id_kp = 128;
enum OBJ_id_kp = "OBJ_id_pkix,3L";

enum SN_id_it = "id-it";
enum NID_id_it = 260;
enum OBJ_id_it = "OBJ_id_pkix,4L";

enum SN_id_pkip = "id-pkip";
enum NID_id_pkip = 261;
enum OBJ_id_pkip = "OBJ_id_pkix,5L";

enum SN_id_alg = "id-alg";
enum NID_id_alg = 262;
enum OBJ_id_alg = "OBJ_id_pkix,6L";

enum SN_id_cmc = "id-cmc";
enum NID_id_cmc = 263;
enum OBJ_id_cmc = "OBJ_id_pkix,7L";

enum SN_id_on = "id-on";
enum NID_id_on = 264;
enum OBJ_id_on = "OBJ_id_pkix,8L";

enum SN_id_pda = "id-pda";
enum NID_id_pda = 265;
enum OBJ_id_pda = "OBJ_id_pkix,9L";

enum SN_id_aca = "id-aca";
enum NID_id_aca = 266;
enum OBJ_id_aca = "OBJ_id_pkix,10L";

enum SN_id_qcs = "id-qcs";
enum NID_id_qcs = 267;
enum OBJ_id_qcs = "OBJ_id_pkix,11L";

enum SN_id_cct = "id-cct";
enum NID_id_cct = 268;
enum OBJ_id_cct = "OBJ_id_pkix,12L";

enum SN_id_ppl = "id-ppl";
enum NID_id_ppl = 662;
enum OBJ_id_ppl = "OBJ_id_pkix,21L";

enum SN_id_ad = "id-ad";
enum NID_id_ad = 176;
enum OBJ_id_ad = "OBJ_id_pkix,48L";

enum SN_id_pkix1_explicit_88 = "id-pkix1-explicit-88";
enum NID_id_pkix1_explicit_88 = 269;
enum OBJ_id_pkix1_explicit_88 = "OBJ_id_pkix_mod,1L";

enum SN_id_pkix1_implicit_88 = "id-pkix1-implicit-88";
enum NID_id_pkix1_implicit_88 = 270;
enum OBJ_id_pkix1_implicit_88 = "OBJ_id_pkix_mod,2L";

enum SN_id_pkix1_explicit_93 = "id-pkix1-explicit-93";
enum NID_id_pkix1_explicit_93 = 271;
enum OBJ_id_pkix1_explicit_93 = "OBJ_id_pkix_mod,3L";

enum SN_id_pkix1_implicit_93 = "id-pkix1-implicit-93";
enum NID_id_pkix1_implicit_93 = 272;
enum OBJ_id_pkix1_implicit_93 = "OBJ_id_pkix_mod,4L";

enum SN_id_mod_crmf = "id-mod-crmf";
enum NID_id_mod_crmf = 273;
enum OBJ_id_mod_crmf = "OBJ_id_pkix_mod,5L";

enum SN_id_mod_cmc = "id-mod-cmc";
enum NID_id_mod_cmc = 274;
enum OBJ_id_mod_cmc = "OBJ_id_pkix_mod,6L";

enum SN_id_mod_kea_profile_88 = "id-mod-kea-profile-88";
enum NID_id_mod_kea_profile_88 = 275;
enum OBJ_id_mod_kea_profile_88 = "OBJ_id_pkix_mod,7L";

enum SN_id_mod_kea_profile_93 = "id-mod-kea-profile-93";
enum NID_id_mod_kea_profile_93 = 276;
enum OBJ_id_mod_kea_profile_93 = "OBJ_id_pkix_mod,8L";

enum SN_id_mod_cmp = "id-mod-cmp";
enum NID_id_mod_cmp = 277;
enum OBJ_id_mod_cmp = "OBJ_id_pkix_mod,9L";

enum SN_id_mod_qualified_cert_88 = "id-mod-qualified-cert-88";
enum NID_id_mod_qualified_cert_88 = 278;
enum OBJ_id_mod_qualified_cert_88 = "OBJ_id_pkix_mod,10L";

enum SN_id_mod_qualified_cert_93 = "id-mod-qualified-cert-93";
enum NID_id_mod_qualified_cert_93 = 279;
enum OBJ_id_mod_qualified_cert_93 = "OBJ_id_pkix_mod,11L";

enum SN_id_mod_attribute_cert = "id-mod-attribute-cert";
enum NID_id_mod_attribute_cert = 280;
enum OBJ_id_mod_attribute_cert = "OBJ_id_pkix_mod,12L";

enum SN_id_mod_timestamp_protocol = "id-mod-timestamp-protocol";
enum NID_id_mod_timestamp_protocol = 281;
enum OBJ_id_mod_timestamp_protocol = "OBJ_id_pkix_mod,13L";

enum SN_id_mod_ocsp = "id-mod-ocsp";
enum NID_id_mod_ocsp = 282;
enum OBJ_id_mod_ocsp = "OBJ_id_pkix_mod,14L";

enum SN_id_mod_dvcs = "id-mod-dvcs";
enum NID_id_mod_dvcs = 283;
enum OBJ_id_mod_dvcs = "OBJ_id_pkix_mod,15L";

enum SN_id_mod_cmp2000 = "id-mod-cmp2000";
enum NID_id_mod_cmp2000 = 284;
enum OBJ_id_mod_cmp2000 = "OBJ_id_pkix_mod,16L";

enum SN_info_access = "authorityInfoAccess";
enum LN_info_access = "Authority Information Access";
enum NID_info_access = 177;
enum OBJ_info_access = "OBJ_id_pe,1L";

enum SN_biometricInfo = "biometricInfo";
enum LN_biometricInfo = "Biometric Info";
enum NID_biometricInfo = 285;
enum OBJ_biometricInfo = "OBJ_id_pe,2L";

enum SN_qcStatements = "qcStatements";
enum NID_qcStatements = 286;
enum OBJ_qcStatements = "OBJ_id_pe,3L";

enum SN_ac_auditEntity = "ac-auditEntity";
enum NID_ac_auditEntity = 287;
enum OBJ_ac_auditEntity = "OBJ_id_pe,4L";

enum SN_ac_targeting = "ac-targeting";
enum NID_ac_targeting = 288;
enum OBJ_ac_targeting = "OBJ_id_pe,5L";

enum SN_aaControls = "aaControls";
enum NID_aaControls = 289;
enum OBJ_aaControls = "OBJ_id_pe,6L";

enum SN_sbgp_ipAddrBlock = "sbgp-ipAddrBlock";
enum NID_sbgp_ipAddrBlock = 290;
enum OBJ_sbgp_ipAddrBlock = "OBJ_id_pe,7L";

enum SN_sbgp_autonomousSysNum = "sbgp-autonomousSysNum";
enum NID_sbgp_autonomousSysNum = 291;
enum OBJ_sbgp_autonomousSysNum = "OBJ_id_pe,8L";

enum SN_sbgp_routerIdentifier = "sbgp-routerIdentifier";
enum NID_sbgp_routerIdentifier = 292;
enum OBJ_sbgp_routerIdentifier = "OBJ_id_pe,9L";

enum SN_ac_proxying = "ac-proxying";
enum NID_ac_proxying = 397;
enum OBJ_ac_proxying = "OBJ_id_pe,10L";

enum SN_sinfo_access = "subjectInfoAccess";
enum LN_sinfo_access = "Subject Information Access";
enum NID_sinfo_access = 398;
enum OBJ_sinfo_access = "OBJ_id_pe,11L";

enum SN_proxyCertInfo = "proxyCertInfo";
enum LN_proxyCertInfo = "Proxy Certificate Information";
enum NID_proxyCertInfo = 663;
enum OBJ_proxyCertInfo = "OBJ_id_pe,14L";

enum SN_id_qt_cps = "id-qt-cps";
enum LN_id_qt_cps = "Policy Qualifier CPS";
enum NID_id_qt_cps = 164;
enum OBJ_id_qt_cps = "OBJ_id_qt,1L";

enum SN_id_qt_unotice = "id-qt-unotice";
enum LN_id_qt_unotice = "Policy Qualifier User Notice";
enum NID_id_qt_unotice = 165;
enum OBJ_id_qt_unotice = "OBJ_id_qt,2L";

enum SN_textNotice = "textNotice";
enum NID_textNotice = 293;
enum OBJ_textNotice = "OBJ_id_qt,3L";

enum SN_server_auth = "serverAuth";
enum LN_server_auth = "TLS Web Server Authentication";
enum NID_server_auth = 129;
enum OBJ_server_auth = "OBJ_id_kp,1L";

enum SN_client_auth = "clientAuth";
enum LN_client_auth = "TLS Web Client Authentication";
enum NID_client_auth = 130;
enum OBJ_client_auth = "OBJ_id_kp,2L";

enum SN_code_sign = "codeSigning";
enum LN_code_sign = "Code Signing";
enum NID_code_sign = 131;
enum OBJ_code_sign = "OBJ_id_kp,3L";

enum SN_email_protect = "emailProtection";
enum LN_email_protect = "E-mail Protection";
enum NID_email_protect = 132;
enum OBJ_email_protect = "OBJ_id_kp,4L";

enum SN_ipsecEndSystem = "ipsecEndSystem";
enum LN_ipsecEndSystem = "IPSec End System";
enum NID_ipsecEndSystem = 294;
enum OBJ_ipsecEndSystem = "OBJ_id_kp,5L";

enum SN_ipsecTunnel = "ipsecTunnel";
enum LN_ipsecTunnel = "IPSec Tunnel";
enum NID_ipsecTunnel = 295;
enum OBJ_ipsecTunnel = "OBJ_id_kp,6L";

enum SN_ipsecUser = "ipsecUser";
enum LN_ipsecUser = "IPSec User";
enum NID_ipsecUser = 296;
enum OBJ_ipsecUser = "OBJ_id_kp,7L";

enum SN_time_stamp = "timeStamping";
enum LN_time_stamp = "Time Stamping";
enum NID_time_stamp = 133;
enum OBJ_time_stamp = "OBJ_id_kp,8L";

enum SN_OCSP_sign = "OCSPSigning";
enum LN_OCSP_sign = "OCSP Signing";
enum NID_OCSP_sign = 180;
enum OBJ_OCSP_sign = "OBJ_id_kp,9L";

enum SN_dvcs = "DVCS";
enum LN_dvcs = "dvcs";
enum NID_dvcs = 297;
enum OBJ_dvcs = "OBJ_id_kp,10L";

enum SN_id_it_caProtEncCert = "id-it-caProtEncCert";
enum NID_id_it_caProtEncCert = 298;
enum OBJ_id_it_caProtEncCert = "OBJ_id_it,1L";

enum SN_id_it_signKeyPairTypes = "id-it-signKeyPairTypes";
enum NID_id_it_signKeyPairTypes = 299;
enum OBJ_id_it_signKeyPairTypes = "OBJ_id_it,2L";

enum SN_id_it_encKeyPairTypes = "id-it-encKeyPairTypes";
enum NID_id_it_encKeyPairTypes = 300;
enum OBJ_id_it_encKeyPairTypes = "OBJ_id_it,3L";

enum SN_id_it_preferredSymmAlg = "id-it-preferredSymmAlg";
enum NID_id_it_preferredSymmAlg = 301;
enum OBJ_id_it_preferredSymmAlg = "OBJ_id_it,4L";

enum SN_id_it_caKeyUpdateInfo = "id-it-caKeyUpdateInfo";
enum NID_id_it_caKeyUpdateInfo = 302;
enum OBJ_id_it_caKeyUpdateInfo = "OBJ_id_it,5L";

enum SN_id_it_currentCRL = "id-it-currentCRL";
enum NID_id_it_currentCRL = 303;
enum OBJ_id_it_currentCRL = "OBJ_id_it,6L";

enum SN_id_it_unsupportedOIDs = "id-it-unsupportedOIDs";
enum NID_id_it_unsupportedOIDs = 304;
enum OBJ_id_it_unsupportedOIDs = "OBJ_id_it,7L";

enum SN_id_it_subscriptionRequest = "id-it-subscriptionRequest";
enum NID_id_it_subscriptionRequest = 305;
enum OBJ_id_it_subscriptionRequest = "OBJ_id_it,8L";

enum SN_id_it_subscriptionResponse = "id-it-subscriptionResponse";
enum NID_id_it_subscriptionResponse = 306;
enum OBJ_id_it_subscriptionResponse = "OBJ_id_it,9L";

enum SN_id_it_keyPairParamReq = "id-it-keyPairParamReq";
enum NID_id_it_keyPairParamReq = 307;
enum OBJ_id_it_keyPairParamReq = "OBJ_id_it,10L";

enum SN_id_it_keyPairParamRep = "id-it-keyPairParamRep";
enum NID_id_it_keyPairParamRep = 308;
enum OBJ_id_it_keyPairParamRep = "OBJ_id_it,11L";

enum SN_id_it_revPassphrase = "id-it-revPassphrase";
enum NID_id_it_revPassphrase = 309;
enum OBJ_id_it_revPassphrase = "OBJ_id_it,12L";

enum SN_id_it_implicitConfirm = "id-it-implicitConfirm";
enum NID_id_it_implicitConfirm = 310;
enum OBJ_id_it_implicitConfirm = "OBJ_id_it,13L";

enum SN_id_it_confirmWaitTime = "id-it-confirmWaitTime";
enum NID_id_it_confirmWaitTime = 311;
enum OBJ_id_it_confirmWaitTime = "OBJ_id_it,14L";

enum SN_id_it_origPKIMessage = "id-it-origPKIMessage";
enum NID_id_it_origPKIMessage = 312;
enum OBJ_id_it_origPKIMessage = "OBJ_id_it,15L";

enum SN_id_it_suppLangTags = "id-it-suppLangTags";
enum NID_id_it_suppLangTags = 784;
enum OBJ_id_it_suppLangTags = "OBJ_id_it,16L";

enum SN_id_regCtrl = "id-regCtrl";
enum NID_id_regCtrl = 313;
enum OBJ_id_regCtrl = "OBJ_id_pkip,1L";

enum SN_id_regInfo = "id-regInfo";
enum NID_id_regInfo = 314;
enum OBJ_id_regInfo = "OBJ_id_pkip,2L";

enum SN_id_regCtrl_regToken = "id-regCtrl-regToken";
enum NID_id_regCtrl_regToken = 315;
enum OBJ_id_regCtrl_regToken = "OBJ_id_regCtrl,1L";

enum SN_id_regCtrl_authenticator = "id-regCtrl-authenticator";
enum NID_id_regCtrl_authenticator = 316;
enum OBJ_id_regCtrl_authenticator = "OBJ_id_regCtrl,2L";

enum SN_id_regCtrl_pkiPublicationInfo = "id-regCtrl-pkiPublicationInfo";
enum NID_id_regCtrl_pkiPublicationInfo = 317;
enum OBJ_id_regCtrl_pkiPublicationInfo = "OBJ_id_regCtrl,3L";

enum SN_id_regCtrl_pkiArchiveOptions = "id-regCtrl-pkiArchiveOptions";
enum NID_id_regCtrl_pkiArchiveOptions = 318;
enum OBJ_id_regCtrl_pkiArchiveOptions = "OBJ_id_regCtrl,4L";

enum SN_id_regCtrl_oldCertID = "id-regCtrl-oldCertID";
enum NID_id_regCtrl_oldCertID = 319;
enum OBJ_id_regCtrl_oldCertID = "OBJ_id_regCtrl,5L";

enum SN_id_regCtrl_protocolEncrKey = "id-regCtrl-protocolEncrKey";
enum NID_id_regCtrl_protocolEncrKey = 320;
enum OBJ_id_regCtrl_protocolEncrKey = "OBJ_id_regCtrl,6L";

enum SN_id_regInfo_utf8Pairs = "id-regInfo-utf8Pairs";
enum NID_id_regInfo_utf8Pairs = 321;
enum OBJ_id_regInfo_utf8Pairs = "OBJ_id_regInfo,1L";

enum SN_id_regInfo_certReq = "id-regInfo-certReq";
enum NID_id_regInfo_certReq = 322;
enum OBJ_id_regInfo_certReq = "OBJ_id_regInfo,2L";

enum SN_id_alg_des40 = "id-alg-des40";
enum NID_id_alg_des40 = 323;
enum OBJ_id_alg_des40 = "OBJ_id_alg,1L";

enum SN_id_alg_noSignature = "id-alg-noSignature";
enum NID_id_alg_noSignature = 324;
enum OBJ_id_alg_noSignature = "OBJ_id_alg,2L";

enum SN_id_alg_dh_sig_hmac_sha1 = "id-alg-dh-sig-hmac-sha1";
enum NID_id_alg_dh_sig_hmac_sha1 = 325;
enum OBJ_id_alg_dh_sig_hmac_sha1 = "OBJ_id_alg,3L";

enum SN_id_alg_dh_pop = "id-alg-dh-pop";
enum NID_id_alg_dh_pop = 326;
enum OBJ_id_alg_dh_pop = "OBJ_id_alg,4L";

enum SN_id_cmc_statusInfo = "id-cmc-statusInfo";
enum NID_id_cmc_statusInfo = 327;
enum OBJ_id_cmc_statusInfo = "OBJ_id_cmc,1L";

enum SN_id_cmc_identification = "id-cmc-identification";
enum NID_id_cmc_identification = 328;
enum OBJ_id_cmc_identification = "OBJ_id_cmc,2L";

enum SN_id_cmc_identityProof = "id-cmc-identityProof";
enum NID_id_cmc_identityProof = 329;
enum OBJ_id_cmc_identityProof = "OBJ_id_cmc,3L";

enum SN_id_cmc_dataReturn = "id-cmc-dataReturn";
enum NID_id_cmc_dataReturn = 330;
enum OBJ_id_cmc_dataReturn = "OBJ_id_cmc,4L";

enum SN_id_cmc_transactionId = "id-cmc-transactionId";
enum NID_id_cmc_transactionId = 331;
enum OBJ_id_cmc_transactionId = "OBJ_id_cmc,5L";

enum SN_id_cmc_senderNonce = "id-cmc-senderNonce";
enum NID_id_cmc_senderNonce = 332;
enum OBJ_id_cmc_senderNonce = "OBJ_id_cmc,6L";

enum SN_id_cmc_recipientNonce = "id-cmc-recipientNonce";
enum NID_id_cmc_recipientNonce = 333;
enum OBJ_id_cmc_recipientNonce = "OBJ_id_cmc,7L";

enum SN_id_cmc_addExtensions = "id-cmc-addExtensions";
enum NID_id_cmc_addExtensions = 334;
enum OBJ_id_cmc_addExtensions = "OBJ_id_cmc,8L";

enum SN_id_cmc_encryptedPOP = "id-cmc-encryptedPOP";
enum NID_id_cmc_encryptedPOP = 335;
enum OBJ_id_cmc_encryptedPOP = "OBJ_id_cmc,9L";

enum SN_id_cmc_decryptedPOP = "id-cmc-decryptedPOP";
enum NID_id_cmc_decryptedPOP = 336;
enum OBJ_id_cmc_decryptedPOP = "OBJ_id_cmc,10L";

enum SN_id_cmc_lraPOPWitness = "id-cmc-lraPOPWitness";
enum NID_id_cmc_lraPOPWitness = 337;
enum OBJ_id_cmc_lraPOPWitness = "OBJ_id_cmc,11L";

enum SN_id_cmc_getCert = "id-cmc-getCert";
enum NID_id_cmc_getCert = 338;
enum OBJ_id_cmc_getCert = "OBJ_id_cmc,15L";

enum SN_id_cmc_getCRL = "id-cmc-getCRL";
enum NID_id_cmc_getCRL = 339;
enum OBJ_id_cmc_getCRL = "OBJ_id_cmc,16L";

enum SN_id_cmc_revokeRequest = "id-cmc-revokeRequest";
enum NID_id_cmc_revokeRequest = 340;
enum OBJ_id_cmc_revokeRequest = "OBJ_id_cmc,17L";

enum SN_id_cmc_regInfo = "id-cmc-regInfo";
enum NID_id_cmc_regInfo = 341;
enum OBJ_id_cmc_regInfo = "OBJ_id_cmc,18L";

enum SN_id_cmc_responseInfo = "id-cmc-responseInfo";
enum NID_id_cmc_responseInfo = 342;
enum OBJ_id_cmc_responseInfo = "OBJ_id_cmc,19L";

enum SN_id_cmc_queryPending = "id-cmc-queryPending";
enum NID_id_cmc_queryPending = 343;
enum OBJ_id_cmc_queryPending = "OBJ_id_cmc,21L";

enum SN_id_cmc_popLinkRandom = "id-cmc-popLinkRandom";
enum NID_id_cmc_popLinkRandom = 344;
enum OBJ_id_cmc_popLinkRandom = "OBJ_id_cmc,22L";

enum SN_id_cmc_popLinkWitness = "id-cmc-popLinkWitness";
enum NID_id_cmc_popLinkWitness = 345;
enum OBJ_id_cmc_popLinkWitness = "OBJ_id_cmc,23L";

enum SN_id_cmc_confirmCertAcceptance = "id-cmc-confirmCertAcceptance";
enum NID_id_cmc_confirmCertAcceptance = 346;
enum OBJ_id_cmc_confirmCertAcceptance = "OBJ_id_cmc,24L";

enum SN_id_on_personalData = "id-on-personalData";
enum NID_id_on_personalData = 347;
enum OBJ_id_on_personalData = "OBJ_id_on,1L";

enum SN_id_on_permanentIdentifier = "id-on-permanentIdentifier";
enum LN_id_on_permanentIdentifier = "Permanent Identifier";
enum NID_id_on_permanentIdentifier = 858;
enum OBJ_id_on_permanentIdentifier = "OBJ_id_on,3L";

enum SN_id_pda_dateOfBirth = "id-pda-dateOfBirth";
enum NID_id_pda_dateOfBirth = 348;
enum OBJ_id_pda_dateOfBirth = "OBJ_id_pda,1L";

enum SN_id_pda_placeOfBirth = "id-pda-placeOfBirth";
enum NID_id_pda_placeOfBirth = 349;
enum OBJ_id_pda_placeOfBirth = "OBJ_id_pda,2L";

enum SN_id_pda_gender = "id-pda-gender";
enum NID_id_pda_gender = 351;
enum OBJ_id_pda_gender = "OBJ_id_pda,3L";

enum SN_id_pda_countryOfCitizenship = "id-pda-countryOfCitizenship";
enum NID_id_pda_countryOfCitizenship = 352;
enum OBJ_id_pda_countryOfCitizenship = "OBJ_id_pda,4L";

enum SN_id_pda_countryOfResidence = "id-pda-countryOfResidence";
enum NID_id_pda_countryOfResidence = 353;
enum OBJ_id_pda_countryOfResidence = "OBJ_id_pda,5L";

enum SN_id_aca_authenticationInfo = "id-aca-authenticationInfo";
enum NID_id_aca_authenticationInfo = 354;
enum OBJ_id_aca_authenticationInfo = "OBJ_id_aca,1L";

enum SN_id_aca_accessIdentity = "id-aca-accessIdentity";
enum NID_id_aca_accessIdentity = 355;
enum OBJ_id_aca_accessIdentity = "OBJ_id_aca,2L";

enum SN_id_aca_chargingIdentity = "id-aca-chargingIdentity";
enum NID_id_aca_chargingIdentity = 356;
enum OBJ_id_aca_chargingIdentity = "OBJ_id_aca,3L";

enum SN_id_aca_group = "id-aca-group";
enum NID_id_aca_group = 357;
enum OBJ_id_aca_group = "OBJ_id_aca,4L";

enum SN_id_aca_role = "id-aca-role";
enum NID_id_aca_role = 358;
enum OBJ_id_aca_role = "OBJ_id_aca,5L";

enum SN_id_aca_encAttrs = "id-aca-encAttrs";
enum NID_id_aca_encAttrs = 399;
enum OBJ_id_aca_encAttrs = "OBJ_id_aca,6L";

enum SN_id_qcs_pkixQCSyntax_v1 = "id-qcs-pkixQCSyntax-v1";
enum NID_id_qcs_pkixQCSyntax_v1 = 359;
enum OBJ_id_qcs_pkixQCSyntax_v1 = "OBJ_id_qcs,1L";

enum SN_id_cct_crs = "id-cct-crs";
enum NID_id_cct_crs = 360;
enum OBJ_id_cct_crs = "OBJ_id_cct,1L";

enum SN_id_cct_PKIData = "id-cct-PKIData";
enum NID_id_cct_PKIData = 361;
enum OBJ_id_cct_PKIData = "OBJ_id_cct,2L";

enum SN_id_cct_PKIResponse = "id-cct-PKIResponse";
enum NID_id_cct_PKIResponse = 362;
enum OBJ_id_cct_PKIResponse = "OBJ_id_cct,3L";

enum SN_id_ppl_anyLanguage = "id-ppl-anyLanguage";
enum LN_id_ppl_anyLanguage = "Any language";
enum NID_id_ppl_anyLanguage = 664;
enum OBJ_id_ppl_anyLanguage = "OBJ_id_ppl,0L";

enum SN_id_ppl_inheritAll = "id-ppl-inheritAll";
enum LN_id_ppl_inheritAll = "Inherit all";
enum NID_id_ppl_inheritAll = 665;
enum OBJ_id_ppl_inheritAll = "OBJ_id_ppl,1L";

enum SN_Independent = "id-ppl-independent";
enum LN_Independent = "Independent";
enum NID_Independent = 667;
enum OBJ_Independent = "OBJ_id_ppl,2L";

enum SN_ad_OCSP = "OCSP";
enum LN_ad_OCSP = "OCSP";
enum NID_ad_OCSP = 178;
enum OBJ_ad_OCSP = "OBJ_id_ad,1L";

enum SN_ad_ca_issuers = "caIssuers";
enum LN_ad_ca_issuers = "CA Issuers";
enum NID_ad_ca_issuers = 179;
enum OBJ_ad_ca_issuers = "OBJ_id_ad,2L";

enum SN_ad_timeStamping = "ad_timestamping";
enum LN_ad_timeStamping = "AD Time Stamping";
enum NID_ad_timeStamping = 363;
enum OBJ_ad_timeStamping = "OBJ_id_ad,3L";

enum SN_ad_dvcs = "AD_DVCS";
enum LN_ad_dvcs = "ad dvcs";
enum NID_ad_dvcs = 364;
enum OBJ_ad_dvcs = "OBJ_id_ad,4L";

enum SN_caRepository = "caRepository";
enum LN_caRepository = "CA Repository";
enum NID_caRepository = 785;
enum OBJ_caRepository = "OBJ_id_ad,5L";

enum OBJ_id_pkix_OCSP = "OBJ_ad_OCSP";

enum SN_id_pkix_OCSP_basic = "basicOCSPResponse";
enum LN_id_pkix_OCSP_basic = "Basic OCSP Response";
enum NID_id_pkix_OCSP_basic = 365;
enum OBJ_id_pkix_OCSP_basic = "OBJ_id_pkix_OCSP,1L";

enum SN_id_pkix_OCSP_Nonce = "Nonce";
enum LN_id_pkix_OCSP_Nonce = "OCSP Nonce";
enum NID_id_pkix_OCSP_Nonce = 366;
enum OBJ_id_pkix_OCSP_Nonce = "OBJ_id_pkix_OCSP,2L";

enum SN_id_pkix_OCSP_CrlID = "CrlID";
enum LN_id_pkix_OCSP_CrlID = "OCSP CRL ID";
enum NID_id_pkix_OCSP_CrlID = 367;
enum OBJ_id_pkix_OCSP_CrlID = "OBJ_id_pkix_OCSP,3L";

enum SN_id_pkix_OCSP_acceptableResponses = "acceptableResponses";
enum LN_id_pkix_OCSP_acceptableResponses = "Acceptable OCSP Responses";
enum NID_id_pkix_OCSP_acceptableResponses = 368;
enum OBJ_id_pkix_OCSP_acceptableResponses = "OBJ_id_pkix_OCSP,4L";

enum SN_id_pkix_OCSP_noCheck = "noCheck";
enum LN_id_pkix_OCSP_noCheck = "OCSP No Check";
enum NID_id_pkix_OCSP_noCheck = 369;
enum OBJ_id_pkix_OCSP_noCheck = "OBJ_id_pkix_OCSP,5L";

enum SN_id_pkix_OCSP_archiveCutoff = "archiveCutoff";
enum LN_id_pkix_OCSP_archiveCutoff = "OCSP Archive Cutoff";
enum NID_id_pkix_OCSP_archiveCutoff = 370;
enum OBJ_id_pkix_OCSP_archiveCutoff = "OBJ_id_pkix_OCSP,6L";

enum SN_id_pkix_OCSP_serviceLocator = "serviceLocator";
enum LN_id_pkix_OCSP_serviceLocator = "OCSP Service Locator";
enum NID_id_pkix_OCSP_serviceLocator = 371;
enum OBJ_id_pkix_OCSP_serviceLocator = "OBJ_id_pkix_OCSP,7L";

enum SN_id_pkix_OCSP_extendedStatus = "extendedStatus";
enum LN_id_pkix_OCSP_extendedStatus = "Extended OCSP Status";
enum NID_id_pkix_OCSP_extendedStatus = 372;
enum OBJ_id_pkix_OCSP_extendedStatus = "OBJ_id_pkix_OCSP,8L";

enum SN_id_pkix_OCSP_valid = "valid";
enum NID_id_pkix_OCSP_valid = 373;
enum OBJ_id_pkix_OCSP_valid = "OBJ_id_pkix_OCSP,9L";

enum SN_id_pkix_OCSP_path = "path";
enum NID_id_pkix_OCSP_path = 374;
enum OBJ_id_pkix_OCSP_path = "OBJ_id_pkix_OCSP,10L";

enum SN_id_pkix_OCSP_trustRoot = "trustRoot";
enum LN_id_pkix_OCSP_trustRoot = "Trust Root";
enum NID_id_pkix_OCSP_trustRoot = 375;
enum OBJ_id_pkix_OCSP_trustRoot = "OBJ_id_pkix_OCSP,11L";

enum SN_algorithm = "algorithm";
enum LN_algorithm = "algorithm";
enum NID_algorithm = 376;
enum OBJ_algorithm = "1L,3L,14L,3L,2L";

enum SN_md5WithRSA = "RSA-NP-MD5";
enum LN_md5WithRSA = "md5WithRSA";
enum NID_md5WithRSA = 104;
enum OBJ_md5WithRSA = "OBJ_algorithm,3L";

enum SN_des_ecb = "DES-ECB";
enum LN_des_ecb = "des-ecb";
enum NID_des_ecb = 29;
enum OBJ_des_ecb = "OBJ_algorithm,6L";

enum SN_des_cbc = "DES-CBC";
enum LN_des_cbc = "des-cbc";
enum NID_des_cbc = 31;
enum OBJ_des_cbc = "OBJ_algorithm,7L";

enum SN_des_ofb64 = "DES-OFB";
enum LN_des_ofb64 = "des-ofb";
enum NID_des_ofb64 = 45;
enum OBJ_des_ofb64 = "OBJ_algorithm,8L";

enum SN_des_cfb64 = "DES-CFB";
enum LN_des_cfb64 = "des-cfb";
enum NID_des_cfb64 = 30;
enum OBJ_des_cfb64 = "OBJ_algorithm,9L";

enum SN_rsaSignature = "rsaSignature";
enum NID_rsaSignature = 377;
enum OBJ_rsaSignature = "OBJ_algorithm,11L";

enum SN_dsa_2 = "DSA-old";
enum LN_dsa_2 = "dsaEncryption-old";
enum NID_dsa_2 = 67;
enum OBJ_dsa_2 = "OBJ_algorithm,12L";

enum SN_dsaWithSHA = "DSA-SHA";
enum LN_dsaWithSHA = "dsaWithSHA";
enum NID_dsaWithSHA = 66;
enum OBJ_dsaWithSHA = "OBJ_algorithm,13L";

enum SN_shaWithRSAEncryption = "RSA-SHA";
enum LN_shaWithRSAEncryption = "shaWithRSAEncryption";
enum NID_shaWithRSAEncryption = 42;
enum OBJ_shaWithRSAEncryption = "OBJ_algorithm,15L";

enum SN_des_ede_ecb = "DES-EDE";
enum LN_des_ede_ecb = "des-ede";
enum NID_des_ede_ecb = 32;
enum OBJ_des_ede_ecb = "OBJ_algorithm,17L";

enum SN_des_ede3_ecb = "DES-EDE3";
enum LN_des_ede3_ecb = "des-ede3";
enum NID_des_ede3_ecb = 33;

enum SN_des_ede_cbc = "DES-EDE-CBC";
enum LN_des_ede_cbc = "des-ede-cbc";
enum NID_des_ede_cbc = 43;

enum SN_des_ede_cfb64 = "DES-EDE-CFB";
enum LN_des_ede_cfb64 = "des-ede-cfb";
enum NID_des_ede_cfb64 = 60;

enum SN_des_ede3_cfb64 = "DES-EDE3-CFB";
enum LN_des_ede3_cfb64 = "des-ede3-cfb";
enum NID_des_ede3_cfb64 = 61;

enum SN_des_ede_ofb64 = "DES-EDE-OFB";
enum LN_des_ede_ofb64 = "des-ede-ofb";
enum NID_des_ede_ofb64 = 62;

enum SN_des_ede3_ofb64 = "DES-EDE3-OFB";
enum LN_des_ede3_ofb64 = "des-ede3-ofb";
enum NID_des_ede3_ofb64 = 63;

enum SN_desx_cbc = "DESX-CBC";
enum LN_desx_cbc = "desx-cbc";
enum NID_desx_cbc = 80;

enum SN_sha = "SHA";
enum LN_sha = "sha";
enum NID_sha = 41;
enum OBJ_sha = "OBJ_algorithm,18L";

enum SN_sha1 = "SHA1";
enum LN_sha1 = "sha1";
enum NID_sha1 = 64;
enum OBJ_sha1 = "OBJ_algorithm,26L";

enum SN_dsaWithSHA1_2 = "DSA-SHA1-old";
enum LN_dsaWithSHA1_2 = "dsaWithSHA1-old";
enum NID_dsaWithSHA1_2 = 70;
enum OBJ_dsaWithSHA1_2 = "OBJ_algorithm,27L";

enum SN_sha1WithRSA = "RSA-SHA1-2";
enum LN_sha1WithRSA = "sha1WithRSA";
enum NID_sha1WithRSA = 115;
enum OBJ_sha1WithRSA = "OBJ_algorithm,29L";

enum SN_ripemd160 = "RIPEMD160";
enum LN_ripemd160 = "ripemd160";
enum NID_ripemd160 = 117;
enum OBJ_ripemd160 = "1L,3L,36L,3L,2L,1L";

enum SN_ripemd160WithRSA = "RSA-RIPEMD160";
enum LN_ripemd160WithRSA = "ripemd160WithRSA";
enum NID_ripemd160WithRSA = 119;
enum OBJ_ripemd160WithRSA = "1L,3L,36L,3L,3L,1L,2L";

enum SN_sxnet = "SXNetID";
enum LN_sxnet = "Strong Extranet ID";
enum NID_sxnet = 143;
enum OBJ_sxnet = "1L,3L,101L,1L,4L,1L";

enum SN_X500 = "X500";
enum LN_X500 = "directory services (X.500)";
enum NID_X500 = 11;
enum OBJ_X500 = "2L,5L";

enum SN_X509 = "X509";
enum NID_X509 = 12;
enum OBJ_X509 = "OBJ_X500,4L";

enum SN_commonName = "CN";
enum LN_commonName = "commonName";
enum NID_commonName = 13;
enum OBJ_commonName = "OBJ_X509,3L";

enum SN_surname = "SN";
enum LN_surname = "surname";
enum NID_surname = 100;
enum OBJ_surname = "OBJ_X509,4L";

enum LN_serialNumber = "serialNumber";
enum NID_serialNumber = 105;
enum OBJ_serialNumber = "OBJ_X509,5L";

enum SN_countryName = "C";
enum LN_countryName = "countryName";
enum NID_countryName = 14;
enum OBJ_countryName = "OBJ_X509,6L";

enum SN_localityName = "L";
enum LN_localityName = "localityName";
enum NID_localityName = 15;
enum OBJ_localityName = "OBJ_X509,7L";

enum SN_stateOrProvinceName = "ST";
enum LN_stateOrProvinceName = "stateOrProvinceName";
enum NID_stateOrProvinceName = 16;
enum OBJ_stateOrProvinceName = "OBJ_X509,8L";

enum SN_streetAddress = "street";
enum LN_streetAddress = "streetAddress";
enum NID_streetAddress = 660;
enum OBJ_streetAddress = "OBJ_X509,9L";

enum SN_organizationName = "O";
enum LN_organizationName = "organizationName";
enum NID_organizationName = 17;
enum OBJ_organizationName = "OBJ_X509,10L";

enum SN_organizationalUnitName = "OU";
enum LN_organizationalUnitName = "organizationalUnitName";
enum NID_organizationalUnitName = 18;
enum OBJ_organizationalUnitName = "OBJ_X509,11L";

enum SN_title = "title";
enum LN_title = "title";
enum NID_title = 106;
enum OBJ_title = "OBJ_X509,12L";

enum LN_description = "description";
enum NID_description = 107;
enum OBJ_description = "OBJ_X509,13L";

enum LN_searchGuide = "searchGuide";
enum NID_searchGuide = 859;
enum OBJ_searchGuide = "OBJ_X509,14L";

enum LN_businessCategory = "businessCategory";
enum NID_businessCategory = 860;
enum OBJ_businessCategory = "OBJ_X509,15L";

enum LN_postalAddress = "postalAddress";
enum NID_postalAddress = 861;
enum OBJ_postalAddress = "OBJ_X509,16L";

enum LN_postalCode = "postalCode";
enum NID_postalCode = 661;
enum OBJ_postalCode = "OBJ_X509,17L";

enum LN_postOfficeBox = "postOfficeBox";
enum NID_postOfficeBox = 862;
enum OBJ_postOfficeBox = "OBJ_X509,18L";

enum LN_physicalDeliveryOfficeName = "physicalDeliveryOfficeName";
enum NID_physicalDeliveryOfficeName = 863;
enum OBJ_physicalDeliveryOfficeName = "OBJ_X509,19L";

enum LN_telephoneNumber = "telephoneNumber";
enum NID_telephoneNumber = 864;
enum OBJ_telephoneNumber = "OBJ_X509,20L";

enum LN_telexNumber = "telexNumber";
enum NID_telexNumber = 865;
enum OBJ_telexNumber = "OBJ_X509,21L";

enum LN_teletexTerminalIdentifier = "teletexTerminalIdentifier";
enum NID_teletexTerminalIdentifier = 866;
enum OBJ_teletexTerminalIdentifier = "OBJ_X509,22L";

enum LN_facsimileTelephoneNumber = "facsimileTelephoneNumber";
enum NID_facsimileTelephoneNumber = 867;
enum OBJ_facsimileTelephoneNumber = "OBJ_X509,23L";

enum LN_x121Address = "x121Address";
enum NID_x121Address = 868;
enum OBJ_x121Address = "OBJ_X509,24L";

enum LN_internationaliSDNNumber = "internationaliSDNNumber";
enum NID_internationaliSDNNumber = 869;
enum OBJ_internationaliSDNNumber = "OBJ_X509,25L";

enum LN_registeredAddress = "registeredAddress";
enum NID_registeredAddress = 870;
enum OBJ_registeredAddress = "OBJ_X509,26L";

enum LN_destinationIndicator = "destinationIndicator";
enum NID_destinationIndicator = 871;
enum OBJ_destinationIndicator = "OBJ_X509,27L";

enum LN_preferredDeliveryMethod = "preferredDeliveryMethod";
enum NID_preferredDeliveryMethod = 872;
enum OBJ_preferredDeliveryMethod = "OBJ_X509,28L";

enum LN_presentationAddress = "presentationAddress";
enum NID_presentationAddress = 873;
enum OBJ_presentationAddress = "OBJ_X509,29L";

enum LN_supportedApplicationContext = "supportedApplicationContext";
enum NID_supportedApplicationContext = 874;
enum OBJ_supportedApplicationContext = "OBJ_X509,30L";

enum SN_member = "member";
enum NID_member = 875;
enum OBJ_member = "OBJ_X509,31L";

enum SN_owner = "owner";
enum NID_owner = 876;
enum OBJ_owner = "OBJ_X509,32L";

enum LN_roleOccupant = "roleOccupant";
enum NID_roleOccupant = 877;
enum OBJ_roleOccupant = "OBJ_X509,33L";

enum SN_seeAlso = "seeAlso";
enum NID_seeAlso = 878;
enum OBJ_seeAlso = "OBJ_X509,34L";

enum LN_userPassword = "userPassword";
enum NID_userPassword = 879;
enum OBJ_userPassword = "OBJ_X509,35L";

enum LN_userCertificate = "userCertificate";
enum NID_userCertificate = 880;
enum OBJ_userCertificate = "OBJ_X509,36L";

enum LN_cACertificate = "cACertificate";
enum NID_cACertificate = 881;
enum OBJ_cACertificate = "OBJ_X509,37L";

enum LN_authorityRevocationList = "authorityRevocationList";
enum NID_authorityRevocationList = 882;
enum OBJ_authorityRevocationList = "OBJ_X509,38L";

enum LN_certificateRevocationList = "certificateRevocationList";
enum NID_certificateRevocationList = 883;
enum OBJ_certificateRevocationList = "OBJ_X509,39L";

enum LN_crossCertificatePair = "crossCertificatePair";
enum NID_crossCertificatePair = 884;
enum OBJ_crossCertificatePair = "OBJ_X509,40L";

enum SN_name = "name";
enum LN_name = "name";
enum NID_name = 173;
enum OBJ_name = "OBJ_X509,41L";

enum SN_givenName = "GN";
enum LN_givenName = "givenName";
enum NID_givenName = 99;
enum OBJ_givenName = "OBJ_X509,42L";

enum SN_initials = "initials";
enum LN_initials = "initials";
enum NID_initials = 101;
enum OBJ_initials = "OBJ_X509,43L";

enum LN_generationQualifier = "generationQualifier";
enum NID_generationQualifier = 509;
enum OBJ_generationQualifier = "OBJ_X509,44L";

enum LN_x500UniqueIdentifier = "x500UniqueIdentifier";
enum NID_x500UniqueIdentifier = 503;
enum OBJ_x500UniqueIdentifier = "OBJ_X509,45L";

enum SN_dnQualifier = "dnQualifier";
enum LN_dnQualifier = "dnQualifier";
enum NID_dnQualifier = 174;
enum OBJ_dnQualifier = "OBJ_X509,46L";

enum LN_enhancedSearchGuide = "enhancedSearchGuide";
enum NID_enhancedSearchGuide = 885;
enum OBJ_enhancedSearchGuide = "OBJ_X509,47L";

enum LN_protocolInformation = "protocolInformation";
enum NID_protocolInformation = 886;
enum OBJ_protocolInformation = "OBJ_X509,48L";

enum LN_distinguishedName = "distinguishedName";
enum NID_distinguishedName = 887;
enum OBJ_distinguishedName = "OBJ_X509,49L";

enum LN_uniqueMember = "uniqueMember";
enum NID_uniqueMember = 888;
enum OBJ_uniqueMember = "OBJ_X509,50L";

enum LN_houseIdentifier = "houseIdentifier";
enum NID_houseIdentifier = 889;
enum OBJ_houseIdentifier = "OBJ_X509,51L";

enum LN_supportedAlgorithms = "supportedAlgorithms";
enum NID_supportedAlgorithms = 890;
enum OBJ_supportedAlgorithms = "OBJ_X509,52L";

enum LN_deltaRevocationList = "deltaRevocationList";
enum NID_deltaRevocationList = 891;
enum OBJ_deltaRevocationList = "OBJ_X509,53L";

enum SN_dmdName = "dmdName";
enum NID_dmdName = 892;
enum OBJ_dmdName = "OBJ_X509,54L";

enum LN_pseudonym = "pseudonym";
enum NID_pseudonym = 510;
enum OBJ_pseudonym = "OBJ_X509,65L";

enum SN_role = "role";
enum LN_role = "role";
enum NID_role = 400;
enum OBJ_role = "OBJ_X509,72L";

enum SN_X500algorithms = "X500algorithms";
enum LN_X500algorithms = "directory services - algorithms";
enum NID_X500algorithms = 378;
enum OBJ_X500algorithms = "OBJ_X500,8L";

enum SN_rsa = "RSA";
enum LN_rsa = "rsa";
enum NID_rsa = 19;
enum OBJ_rsa = "OBJ_X500algorithms,1L,1L";

enum SN_mdc2WithRSA = "RSA-MDC2";
enum LN_mdc2WithRSA = "mdc2WithRSA";
enum NID_mdc2WithRSA = 96;
enum OBJ_mdc2WithRSA = "OBJ_X500algorithms,3L,100L";

enum SN_mdc2 = "MDC2";
enum LN_mdc2 = "mdc2";
enum NID_mdc2 = 95;
enum OBJ_mdc2 = "OBJ_X500algorithms,3L,101L";

enum SN_id_ce = "id-ce";
enum NID_id_ce = 81;
enum OBJ_id_ce = "OBJ_X500,29L";

enum SN_subject_directory_attributes = "subjectDirectoryAttributes";
enum LN_subject_directory_attributes = "X509v3 Subject Directory Attributes";
enum NID_subject_directory_attributes = 769;
enum OBJ_subject_directory_attributes = "OBJ_id_ce,9L";

enum SN_subject_key_identifier = "subjectKeyIdentifier";
enum LN_subject_key_identifier = "X509v3 Subject Key Identifier";
enum NID_subject_key_identifier = 82;
enum OBJ_subject_key_identifier = "OBJ_id_ce,14L";

enum SN_key_usage = "keyUsage";
enum LN_key_usage = "X509v3 Key Usage";
enum NID_key_usage = 83;
enum OBJ_key_usage = "OBJ_id_ce,15L";

enum SN_private_key_usage_period = "privateKeyUsagePeriod";
enum LN_private_key_usage_period = "X509v3 Private Key Usage Period";
enum NID_private_key_usage_period = 84;
enum OBJ_private_key_usage_period = "OBJ_id_ce,16L";

enum SN_subject_alt_name = "subjectAltName";
enum LN_subject_alt_name = "X509v3 Subject Alternative Name";
enum NID_subject_alt_name = 85;
enum OBJ_subject_alt_name = "OBJ_id_ce,17L";

enum SN_issuer_alt_name = "issuerAltName";
enum LN_issuer_alt_name = "X509v3 Issuer Alternative Name";
enum NID_issuer_alt_name = 86;
enum OBJ_issuer_alt_name = "OBJ_id_ce,18L";

enum SN_basic_constraints = "basicConstraints";
enum LN_basic_constraints = "X509v3 Basic Constraints";
enum NID_basic_constraints = 87;
enum OBJ_basic_constraints = "OBJ_id_ce,19L";

enum SN_crl_number = "crlNumber";
enum LN_crl_number = "X509v3 CRL Number";
enum NID_crl_number = 88;
enum OBJ_crl_number = "OBJ_id_ce,20L";

enum SN_crl_reason = "CRLReason";
enum LN_crl_reason = "X509v3 CRL Reason Code";
enum NID_crl_reason = 141;
enum OBJ_crl_reason = "OBJ_id_ce,21L";

enum SN_invalidity_date = "invalidityDate";
enum LN_invalidity_date = "Invalidity Date";
enum NID_invalidity_date = 142;
enum OBJ_invalidity_date = "OBJ_id_ce,24L";

enum SN_delta_crl = "deltaCRL";
enum LN_delta_crl = "X509v3 Delta CRL Indicator";
enum NID_delta_crl = 140;
enum OBJ_delta_crl = "OBJ_id_ce,27L";

enum SN_issuing_distribution_point = "issuingDistributionPoint";
enum LN_issuing_distribution_point = "X509v3 Issuing Distrubution Point";
enum NID_issuing_distribution_point = 770;
enum OBJ_issuing_distribution_point = "OBJ_id_ce,28L";

enum SN_certificate_issuer = "certificateIssuer";
enum LN_certificate_issuer = "X509v3 Certificate Issuer";
enum NID_certificate_issuer = 771;
enum OBJ_certificate_issuer = "OBJ_id_ce,29L";

enum SN_name_constraints = "nameConstraints";
enum LN_name_constraints = "X509v3 Name Constraints";
enum NID_name_constraints = 666;
enum OBJ_name_constraints = "OBJ_id_ce,30L";

enum SN_crl_distribution_points = "crlDistributionPoints";
enum LN_crl_distribution_points = "X509v3 CRL Distribution Points";
enum NID_crl_distribution_points = 103;
enum OBJ_crl_distribution_points = "OBJ_id_ce,31L";

enum SN_certificate_policies = "certificatePolicies";
enum LN_certificate_policies = "X509v3 Certificate Policies";
enum NID_certificate_policies = 89;
enum OBJ_certificate_policies = "OBJ_id_ce,32L";

enum SN_any_policy = "anyPolicy";
enum LN_any_policy = "X509v3 Any Policy";
enum NID_any_policy = 746;
enum OBJ_any_policy = "OBJ_certificate_policies,0L";

enum SN_policy_mappings = "policyMappings";
enum LN_policy_mappings = "X509v3 Policy Mappings";
enum NID_policy_mappings = 747;
enum OBJ_policy_mappings = "OBJ_id_ce,33L";

enum SN_authority_key_identifier = "authorityKeyIdentifier";
enum LN_authority_key_identifier = "X509v3 Authority Key Identifier";
enum NID_authority_key_identifier = 90;
enum OBJ_authority_key_identifier = "OBJ_id_ce,35L";

enum SN_policy_constraints = "policyConstraints";
enum LN_policy_constraints = "X509v3 Policy Constraints";
enum NID_policy_constraints = 401;
enum OBJ_policy_constraints = "OBJ_id_ce,36L";

enum SN_ext_key_usage = "extendedKeyUsage";
enum LN_ext_key_usage = "X509v3 Extended Key Usage";
enum NID_ext_key_usage = 126;
enum OBJ_ext_key_usage = "OBJ_id_ce,37L";

enum SN_freshest_crl = "freshestCRL";
enum LN_freshest_crl = "X509v3 Freshest CRL";
enum NID_freshest_crl = 857;
enum OBJ_freshest_crl = "OBJ_id_ce,46L";

enum SN_inhibit_any_policy = "inhibitAnyPolicy";
enum LN_inhibit_any_policy = "X509v3 Inhibit Any Policy";
enum NID_inhibit_any_policy = 748;
enum OBJ_inhibit_any_policy = "OBJ_id_ce,54L";

enum SN_target_information = "targetInformation";
enum LN_target_information = "X509v3 AC Targeting";
enum NID_target_information = 402;
enum OBJ_target_information = "OBJ_id_ce,55L";

enum SN_no_rev_avail = "noRevAvail";
enum LN_no_rev_avail = "X509v3 No Revocation Available";
enum NID_no_rev_avail = 403;
enum OBJ_no_rev_avail = "OBJ_id_ce,56L";

enum SN_netscape = "Netscape";
enum LN_netscape = "Netscape Communications Corp.";
enum NID_netscape = 57;
enum OBJ_netscape = "2L,16L,840L,1L,113730L";

enum SN_netscape_cert_extension = "nsCertExt";
enum LN_netscape_cert_extension = "Netscape Certificate Extension";
enum NID_netscape_cert_extension = 58;
enum OBJ_netscape_cert_extension = "OBJ_netscape,1L";

enum SN_netscape_data_type = "nsDataType";
enum LN_netscape_data_type = "Netscape Data Type";
enum NID_netscape_data_type = 59;
enum OBJ_netscape_data_type = "OBJ_netscape,2L";

enum SN_netscape_cert_type = "nsCertType";
enum LN_netscape_cert_type = "Netscape Cert Type";
enum NID_netscape_cert_type = 71;
enum OBJ_netscape_cert_type = "OBJ_netscape_cert_extension,1L";

enum SN_netscape_base_url = "nsBaseUrl";
enum LN_netscape_base_url = "Netscape Base Url";
enum NID_netscape_base_url = 72;
enum OBJ_netscape_base_url = "OBJ_netscape_cert_extension,2L";

enum SN_netscape_revocation_url = "nsRevocationUrl";
enum LN_netscape_revocation_url = "Netscape Revocation Url";
enum NID_netscape_revocation_url = 73;
enum OBJ_netscape_revocation_url = "OBJ_netscape_cert_extension,3L";

enum SN_netscape_ca_revocation_url = "nsCaRevocationUrl";
enum LN_netscape_ca_revocation_url = "Netscape CA Revocation Url";
enum NID_netscape_ca_revocation_url = 74;
enum OBJ_netscape_ca_revocation_url = "OBJ_netscape_cert_extension,4L";

enum SN_netscape_renewal_url = "nsRenewalUrl";
enum LN_netscape_renewal_url = "Netscape Renewal Url";
enum NID_netscape_renewal_url = 75;
enum OBJ_netscape_renewal_url = "OBJ_netscape_cert_extension,7L";

enum SN_netscape_ca_policy_url = "nsCaPolicyUrl";
enum LN_netscape_ca_policy_url = "Netscape CA Policy Url";
enum NID_netscape_ca_policy_url = 76;
enum OBJ_netscape_ca_policy_url = "OBJ_netscape_cert_extension,8L";

enum SN_netscape_ssl_server_name = "nsSslServerName";
enum LN_netscape_ssl_server_name = "Netscape SSL Server Name";
enum NID_netscape_ssl_server_name = 77;
enum OBJ_netscape_ssl_server_name = "OBJ_netscape_cert_extension,12L";

enum SN_netscape_comment = "nsComment";
enum LN_netscape_comment = "Netscape Comment";
enum NID_netscape_comment = 78;
enum OBJ_netscape_comment = "OBJ_netscape_cert_extension,13L";

enum SN_netscape_cert_sequence = "nsCertSequence";
enum LN_netscape_cert_sequence = "Netscape Certificate Sequence";
enum NID_netscape_cert_sequence = 79;
enum OBJ_netscape_cert_sequence = "OBJ_netscape_data_type,5L";

enum SN_ns_sgc = "nsSGC";
enum LN_ns_sgc = "Netscape Server Gated Crypto";
enum NID_ns_sgc = 139;
enum OBJ_ns_sgc = "OBJ_netscape,4L,1L";

enum SN_org = "ORG";
enum LN_org = "org";
enum NID_org = 379;
enum OBJ_org = "OBJ_iso,3L";

enum SN_dod = "DOD";
enum LN_dod = "dod";
enum NID_dod = 380;
enum OBJ_dod = "OBJ_org,6L";

enum SN_iana = "IANA";
enum LN_iana = "iana";
enum NID_iana = 381;
enum OBJ_iana = "OBJ_dod,1L";

enum OBJ_internet = "OBJ_iana";

enum SN_Directory = "directory";
enum LN_Directory = "Directory";
enum NID_Directory = 382;
enum OBJ_Directory = "OBJ_internet,1L";

enum SN_Management = "mgmt";
enum LN_Management = "Management";
enum NID_Management = 383;
enum OBJ_Management = "OBJ_internet,2L";

enum SN_Experimental = "experimental";
enum LN_Experimental = "Experimental";
enum NID_Experimental = 384;
enum OBJ_Experimental = "OBJ_internet,3L";

enum SN_Private = "private";
enum LN_Private = "Private";
enum NID_Private = 385;
enum OBJ_Private = "OBJ_internet,4L";

enum SN_Security = "security";
enum LN_Security = "Security";
enum NID_Security = 386;
enum OBJ_Security = "OBJ_internet,5L";

enum SN_SNMPv2 = "snmpv2";
enum LN_SNMPv2 = "SNMPv2";
enum NID_SNMPv2 = 387;
enum OBJ_SNMPv2 = "OBJ_internet,6L";

enum LN_Mail = "Mail";
enum NID_Mail = 388;
enum OBJ_Mail = "OBJ_internet,7L";

enum SN_Enterprises = "enterprises";
enum LN_Enterprises = "Enterprises";
enum NID_Enterprises = 389;
enum OBJ_Enterprises = "OBJ_Private,1L";

enum SN_dcObject = "dcobject";
enum LN_dcObject = "dcObject";
enum NID_dcObject = 390;
enum OBJ_dcObject = "OBJ_Enterprises,1466L,344L";

enum SN_mime_mhs = "mime-mhs";
enum LN_mime_mhs = "MIME MHS";
enum NID_mime_mhs = 504;
enum OBJ_mime_mhs = "OBJ_Mail,1L";

enum SN_mime_mhs_headings = "mime-mhs-headings";
enum LN_mime_mhs_headings = "mime-mhs-headings";
enum NID_mime_mhs_headings = 505;
enum OBJ_mime_mhs_headings = "OBJ_mime_mhs,1L";

enum SN_mime_mhs_bodies = "mime-mhs-bodies";
enum LN_mime_mhs_bodies = "mime-mhs-bodies";
enum NID_mime_mhs_bodies = 506;
enum OBJ_mime_mhs_bodies = "OBJ_mime_mhs,2L";

enum SN_id_hex_partial_message = "id-hex-partial-message";
enum LN_id_hex_partial_message = "id-hex-partial-message";
enum NID_id_hex_partial_message = 507;
enum OBJ_id_hex_partial_message = "OBJ_mime_mhs_headings,1L";

enum SN_id_hex_multipart_message = "id-hex-multipart-message";
enum LN_id_hex_multipart_message = "id-hex-multipart-message";
enum NID_id_hex_multipart_message = 508;
enum OBJ_id_hex_multipart_message = "OBJ_mime_mhs_headings,2L";

enum SN_rle_compression = "RLE";
enum LN_rle_compression = "run length compression";
enum NID_rle_compression = 124;
enum OBJ_rle_compression = "1L,1L,1L,1L,666L,1L";

enum SN_zlib_compression = "ZLIB";
enum LN_zlib_compression = "zlib compression";
enum NID_zlib_compression = 125;
enum OBJ_zlib_compression = "OBJ_id_smime_alg,8L";

enum OBJ_csor = "2L,16L,840L,1L,101L,3L";

enum OBJ_nistAlgorithms = "OBJ_csor,4L";

enum OBJ_aes = "OBJ_nistAlgorithms,1L";

enum SN_aes_128_ecb = "AES-128-ECB";
enum LN_aes_128_ecb = "aes-128-ecb";
enum NID_aes_128_ecb = 418;
enum OBJ_aes_128_ecb = "OBJ_aes,1L";

enum SN_aes_128_cbc = "AES-128-CBC";
enum LN_aes_128_cbc = "aes-128-cbc";
enum NID_aes_128_cbc = 419;
enum OBJ_aes_128_cbc = "OBJ_aes,2L";

enum SN_aes_128_ofb128 = "AES-128-OFB";
enum LN_aes_128_ofb128 = "aes-128-ofb";
enum NID_aes_128_ofb128 = 420;
enum OBJ_aes_128_ofb128 = "OBJ_aes,3L";

enum SN_aes_128_cfb128 = "AES-128-CFB";
enum LN_aes_128_cfb128 = "aes-128-cfb";
enum NID_aes_128_cfb128 = 421;
enum OBJ_aes_128_cfb128 = "OBJ_aes,4L";

enum SN_aes_192_ecb = "AES-192-ECB";
enum LN_aes_192_ecb = "aes-192-ecb";
enum NID_aes_192_ecb = 422;
enum OBJ_aes_192_ecb = "OBJ_aes,21L";

enum SN_aes_192_cbc = "AES-192-CBC";
enum LN_aes_192_cbc = "aes-192-cbc";
enum NID_aes_192_cbc = 423;
enum OBJ_aes_192_cbc = "OBJ_aes,22L";

enum SN_aes_192_ofb128 = "AES-192-OFB";
enum LN_aes_192_ofb128 = "aes-192-ofb";
enum NID_aes_192_ofb128 = 424;
enum OBJ_aes_192_ofb128 = "OBJ_aes,23L";

enum SN_aes_192_cfb128 = "AES-192-CFB";
enum LN_aes_192_cfb128 = "aes-192-cfb";
enum NID_aes_192_cfb128 = 425;
enum OBJ_aes_192_cfb128 = "OBJ_aes,24L";

enum SN_aes_256_ecb = "AES-256-ECB";
enum LN_aes_256_ecb = "aes-256-ecb";
enum NID_aes_256_ecb = 426;
enum OBJ_aes_256_ecb = "OBJ_aes,41L";

enum SN_aes_256_cbc = "AES-256-CBC";
enum LN_aes_256_cbc = "aes-256-cbc";
enum NID_aes_256_cbc = 427;
enum OBJ_aes_256_cbc = "OBJ_aes,42L";

enum SN_aes_256_ofb128 = "AES-256-OFB";
enum LN_aes_256_ofb128 = "aes-256-ofb";
enum NID_aes_256_ofb128 = 428;
enum OBJ_aes_256_ofb128 = "OBJ_aes,43L";

enum SN_aes_256_cfb128 = "AES-256-CFB";
enum LN_aes_256_cfb128 = "aes-256-cfb";
enum NID_aes_256_cfb128 = 429;
enum OBJ_aes_256_cfb128 = "OBJ_aes,44L";

enum SN_aes_128_cfb1 = "AES-128-CFB1";
enum LN_aes_128_cfb1 = "aes-128-cfb1";
enum NID_aes_128_cfb1 = 650;

enum SN_aes_192_cfb1 = "AES-192-CFB1";
enum LN_aes_192_cfb1 = "aes-192-cfb1";
enum NID_aes_192_cfb1 = 651;

enum SN_aes_256_cfb1 = "AES-256-CFB1";
enum LN_aes_256_cfb1 = "aes-256-cfb1";
enum NID_aes_256_cfb1 = 652;

enum SN_aes_128_cfb8 = "AES-128-CFB8";
enum LN_aes_128_cfb8 = "aes-128-cfb8";
enum NID_aes_128_cfb8 = 653;

enum SN_aes_192_cfb8 = "AES-192-CFB8";
enum LN_aes_192_cfb8 = "aes-192-cfb8";
enum NID_aes_192_cfb8 = 654;

enum SN_aes_256_cfb8 = "AES-256-CFB8";
enum LN_aes_256_cfb8 = "aes-256-cfb8";
enum NID_aes_256_cfb8 = 655;

enum SN_des_cfb1 = "DES-CFB1";
enum LN_des_cfb1 = "des-cfb1";
enum NID_des_cfb1 = 656;

enum SN_des_cfb8 = "DES-CFB8";
enum LN_des_cfb8 = "des-cfb8";
enum NID_des_cfb8 = 657;

enum SN_des_ede3_cfb1 = "DES-EDE3-CFB1";
enum LN_des_ede3_cfb1 = "des-ede3-cfb1";
enum NID_des_ede3_cfb1 = 658;

enum SN_des_ede3_cfb8 = "DES-EDE3-CFB8";
enum LN_des_ede3_cfb8 = "des-ede3-cfb8";
enum NID_des_ede3_cfb8 = 659;

enum SN_id_aes128_wrap = "id-aes128-wrap";
enum NID_id_aes128_wrap = 788;
enum OBJ_id_aes128_wrap = "OBJ_aes,5L";

enum SN_id_aes192_wrap = "id-aes192-wrap";
enum NID_id_aes192_wrap = 789;
enum OBJ_id_aes192_wrap = "OBJ_aes,25L";

enum SN_id_aes256_wrap = "id-aes256-wrap";
enum NID_id_aes256_wrap = 790;
enum OBJ_id_aes256_wrap = "OBJ_aes,45L";

enum OBJ_nist_hashalgs = "OBJ_nistAlgorithms,2L";

enum SN_sha256 = "SHA256";
enum LN_sha256 = "sha256";
enum NID_sha256 = 672;
enum OBJ_sha256 = "OBJ_nist_hashalgs,1L";

enum SN_sha384 = "SHA384";
enum LN_sha384 = "sha384";
enum NID_sha384 = 673;
enum OBJ_sha384 = "OBJ_nist_hashalgs,2L";

enum SN_sha512 = "SHA512";
enum LN_sha512 = "sha512";
enum NID_sha512 = 674;
enum OBJ_sha512 = "OBJ_nist_hashalgs,3L";

enum SN_sha224 = "SHA224";
enum LN_sha224 = "sha224";
enum NID_sha224 = 675;
enum OBJ_sha224 = "OBJ_nist_hashalgs,4L";

enum OBJ_dsa_with_sha2 = "OBJ_nistAlgorithms,3L";

enum SN_dsa_with_SHA224 = "dsa_with_SHA224";
enum NID_dsa_with_SHA224 = 802;
enum OBJ_dsa_with_SHA224 = "OBJ_dsa_with_sha2,1L";

enum SN_dsa_with_SHA256 = "dsa_with_SHA256";
enum NID_dsa_with_SHA256 = 803;
enum OBJ_dsa_with_SHA256 = "OBJ_dsa_with_sha2,2L";

enum SN_hold_instruction_code = "holdInstructionCode";
enum LN_hold_instruction_code = "Hold Instruction Code";
enum NID_hold_instruction_code = 430;
enum OBJ_hold_instruction_code = "OBJ_id_ce,23L";

enum OBJ_holdInstruction = "OBJ_X9_57,2L";

enum SN_hold_instruction_none = "holdInstructionNone";
enum LN_hold_instruction_none = "Hold Instruction None";
enum NID_hold_instruction_none = 431;
enum OBJ_hold_instruction_none = "OBJ_holdInstruction,1L";

enum SN_hold_instruction_call_issuer = "holdInstructionCallIssuer";
enum LN_hold_instruction_call_issuer = "Hold Instruction Call Issuer";
enum NID_hold_instruction_call_issuer = 432;
enum OBJ_hold_instruction_call_issuer = "OBJ_holdInstruction,2L";

enum SN_hold_instruction_reject = "holdInstructionReject";
enum LN_hold_instruction_reject = "Hold Instruction Reject";
enum NID_hold_instruction_reject = 433;
enum OBJ_hold_instruction_reject = "OBJ_holdInstruction,3L";

enum SN_data = "data";
enum NID_data = 434;
enum OBJ_data = "OBJ_itu_t,9L";

enum SN_pss = "pss";
enum NID_pss = 435;
enum OBJ_pss = "OBJ_data,2342L";

enum SN_ucl = "ucl";
enum NID_ucl = 436;
enum OBJ_ucl = "OBJ_pss,19200300L";

enum SN_pilot = "pilot";
enum NID_pilot = 437;
enum OBJ_pilot = "OBJ_ucl,100L";

enum LN_pilotAttributeType = "pilotAttributeType";
enum NID_pilotAttributeType = 438;
enum OBJ_pilotAttributeType = "OBJ_pilot,1L";

enum LN_pilotAttributeSyntax = "pilotAttributeSyntax";
enum NID_pilotAttributeSyntax = 439;
enum OBJ_pilotAttributeSyntax = "OBJ_pilot,3L";

enum LN_pilotObjectClass = "pilotObjectClass";
enum NID_pilotObjectClass = 440;
enum OBJ_pilotObjectClass = "OBJ_pilot,4L";

enum LN_pilotGroups = "pilotGroups";
enum NID_pilotGroups = 441;
enum OBJ_pilotGroups = "OBJ_pilot,10L";

enum LN_iA5StringSyntax = "iA5StringSyntax";
enum NID_iA5StringSyntax = 442;
enum OBJ_iA5StringSyntax = "OBJ_pilotAttributeSyntax,4L";

enum LN_caseIgnoreIA5StringSyntax = "caseIgnoreIA5StringSyntax";
enum NID_caseIgnoreIA5StringSyntax = 443;
enum OBJ_caseIgnoreIA5StringSyntax = "OBJ_pilotAttributeSyntax,5L";

enum LN_pilotObject = "pilotObject";
enum NID_pilotObject = 444;
enum OBJ_pilotObject = "OBJ_pilotObjectClass,3L";

enum LN_pilotPerson = "pilotPerson";
enum NID_pilotPerson = 445;
enum OBJ_pilotPerson = "OBJ_pilotObjectClass,4L";

enum SN_account = "account";
enum NID_account = 446;
enum OBJ_account = "OBJ_pilotObjectClass,5L";

enum SN_document = "document";
enum NID_document = 447;
enum OBJ_document = "OBJ_pilotObjectClass,6L";

enum SN_room = "room";
enum NID_room = 448;
enum OBJ_room = "OBJ_pilotObjectClass,7L";

enum LN_documentSeries = "documentSeries";
enum NID_documentSeries = 449;
enum OBJ_documentSeries = "OBJ_pilotObjectClass,9L";

enum SN_Domain = "domain";
enum LN_Domain = "Domain";
enum NID_Domain = 392;
enum OBJ_Domain = "OBJ_pilotObjectClass,13L";

enum LN_rFC822localPart = "rFC822localPart";
enum NID_rFC822localPart = 450;
enum OBJ_rFC822localPart = "OBJ_pilotObjectClass,14L";

enum LN_dNSDomain = "dNSDomain";
enum NID_dNSDomain = 451;
enum OBJ_dNSDomain = "OBJ_pilotObjectClass,15L";

enum LN_domainRelatedObject = "domainRelatedObject";
enum NID_domainRelatedObject = 452;
enum OBJ_domainRelatedObject = "OBJ_pilotObjectClass,17L";

enum LN_friendlyCountry = "friendlyCountry";
enum NID_friendlyCountry = 453;
enum OBJ_friendlyCountry = "OBJ_pilotObjectClass,18L";

enum LN_simpleSecurityObject = "simpleSecurityObject";
enum NID_simpleSecurityObject = 454;
enum OBJ_simpleSecurityObject = "OBJ_pilotObjectClass,19L";

enum LN_pilotOrganization = "pilotOrganization";
enum NID_pilotOrganization = 455;
enum OBJ_pilotOrganization = "OBJ_pilotObjectClass,20L";

enum LN_pilotDSA = "pilotDSA";
enum NID_pilotDSA = 456;
enum OBJ_pilotDSA = "OBJ_pilotObjectClass,21L";

enum LN_qualityLabelledData = "qualityLabelledData";
enum NID_qualityLabelledData = 457;
enum OBJ_qualityLabelledData = "OBJ_pilotObjectClass,22L";

enum SN_userId = "UID";
enum LN_userId = "userId";
enum NID_userId = 458;
enum OBJ_userId = "OBJ_pilotAttributeType,1L";

enum LN_textEncodedORAddress = "textEncodedORAddress";
enum NID_textEncodedORAddress = 459;
enum OBJ_textEncodedORAddress = "OBJ_pilotAttributeType,2L";

enum SN_rfc822Mailbox = "mail";
enum LN_rfc822Mailbox = "rfc822Mailbox";
enum NID_rfc822Mailbox = 460;
enum OBJ_rfc822Mailbox = "OBJ_pilotAttributeType,3L";

enum SN_info = "info";
enum NID_info = 461;
enum OBJ_info = "OBJ_pilotAttributeType,4L";

enum LN_favouriteDrink = "favouriteDrink";
enum NID_favouriteDrink = 462;
enum OBJ_favouriteDrink = "OBJ_pilotAttributeType,5L";

enum LN_roomNumber = "roomNumber";
enum NID_roomNumber = 463;
enum OBJ_roomNumber = "OBJ_pilotAttributeType,6L";

enum SN_photo = "photo";
enum NID_photo = 464;
enum OBJ_photo = "OBJ_pilotAttributeType,7L";

enum LN_userClass = "userClass";
enum NID_userClass = 465;
enum OBJ_userClass = "OBJ_pilotAttributeType,8L";

enum SN_host = "host";
enum NID_host = 466;
enum OBJ_host = "OBJ_pilotAttributeType,9L";

enum SN_manager = "manager";
enum NID_manager = 467;
enum OBJ_manager = "OBJ_pilotAttributeType,10L";

enum LN_documentIdentifier = "documentIdentifier";
enum NID_documentIdentifier = 468;
enum OBJ_documentIdentifier = "OBJ_pilotAttributeType,11L";

enum LN_documentTitle = "documentTitle";
enum NID_documentTitle = 469;
enum OBJ_documentTitle = "OBJ_pilotAttributeType,12L";

enum LN_documentVersion = "documentVersion";
enum NID_documentVersion = 470;
enum OBJ_documentVersion = "OBJ_pilotAttributeType,13L";

enum LN_documentAuthor = "documentAuthor";
enum NID_documentAuthor = 471;
enum OBJ_documentAuthor = "OBJ_pilotAttributeType,14L";

enum LN_documentLocation = "documentLocation";
enum NID_documentLocation = 472;
enum OBJ_documentLocation = "OBJ_pilotAttributeType,15L";

enum LN_homeTelephoneNumber = "homeTelephoneNumber";
enum NID_homeTelephoneNumber = 473;
enum OBJ_homeTelephoneNumber = "OBJ_pilotAttributeType,20L";

enum SN_secretary = "secretary";
enum NID_secretary = 474;
enum OBJ_secretary = "OBJ_pilotAttributeType,21L";

enum LN_otherMailbox = "otherMailbox";
enum NID_otherMailbox = 475;
enum OBJ_otherMailbox = "OBJ_pilotAttributeType,22L";

enum LN_lastModifiedTime = "lastModifiedTime";
enum NID_lastModifiedTime = 476;
enum OBJ_lastModifiedTime = "OBJ_pilotAttributeType,23L";

enum LN_lastModifiedBy = "lastModifiedBy";
enum NID_lastModifiedBy = 477;
enum OBJ_lastModifiedBy = "OBJ_pilotAttributeType,24L";

enum SN_domainComponent = "DC";
enum LN_domainComponent = "domainComponent";
enum NID_domainComponent = 391;
enum OBJ_domainComponent = "OBJ_pilotAttributeType,25L";

enum LN_aRecord = "aRecord";
enum NID_aRecord = 478;
enum OBJ_aRecord = "OBJ_pilotAttributeType,26L";

enum LN_pilotAttributeType27 = "pilotAttributeType27";
enum NID_pilotAttributeType27 = 479;
enum OBJ_pilotAttributeType27 = "OBJ_pilotAttributeType,27L";

enum LN_mXRecord = "mXRecord";
enum NID_mXRecord = 480;
enum OBJ_mXRecord = "OBJ_pilotAttributeType,28L";

enum LN_nSRecord = "nSRecord";
enum NID_nSRecord = 481;
enum OBJ_nSRecord = "OBJ_pilotAttributeType,29L";

enum LN_sOARecord = "sOARecord";
enum NID_sOARecord = 482;
enum OBJ_sOARecord = "OBJ_pilotAttributeType,30L";

enum LN_cNAMERecord = "cNAMERecord";
enum NID_cNAMERecord = 483;
enum OBJ_cNAMERecord = "OBJ_pilotAttributeType,31L";

enum LN_associatedDomain = "associatedDomain";
enum NID_associatedDomain = 484;
enum OBJ_associatedDomain = "OBJ_pilotAttributeType,37L";

enum LN_associatedName = "associatedName";
enum NID_associatedName = 485;
enum OBJ_associatedName = "OBJ_pilotAttributeType,38L";

enum LN_homePostalAddress = "homePostalAddress";
enum NID_homePostalAddress = 486;
enum OBJ_homePostalAddress = "OBJ_pilotAttributeType,39L";

enum LN_personalTitle = "personalTitle";
enum NID_personalTitle = 487;
enum OBJ_personalTitle = "OBJ_pilotAttributeType,40L";

enum LN_mobileTelephoneNumber = "mobileTelephoneNumber";
enum NID_mobileTelephoneNumber = 488;
enum OBJ_mobileTelephoneNumber = "OBJ_pilotAttributeType,41L";

enum LN_pagerTelephoneNumber = "pagerTelephoneNumber";
enum NID_pagerTelephoneNumber = 489;
enum OBJ_pagerTelephoneNumber = "OBJ_pilotAttributeType,42L";

enum LN_friendlyCountryName = "friendlyCountryName";
enum NID_friendlyCountryName = 490;
enum OBJ_friendlyCountryName = "OBJ_pilotAttributeType,43L";

enum LN_organizationalStatus = "organizationalStatus";
enum NID_organizationalStatus = 491;
enum OBJ_organizationalStatus = "OBJ_pilotAttributeType,45L";

enum LN_janetMailbox = "janetMailbox";
enum NID_janetMailbox = 492;
enum OBJ_janetMailbox = "OBJ_pilotAttributeType,46L";

enum LN_mailPreferenceOption = "mailPreferenceOption";
enum NID_mailPreferenceOption = 493;
enum OBJ_mailPreferenceOption = "OBJ_pilotAttributeType,47L";

enum LN_buildingName = "buildingName";
enum NID_buildingName = 494;
enum OBJ_buildingName = "OBJ_pilotAttributeType,48L";

enum LN_dSAQuality = "dSAQuality";
enum NID_dSAQuality = 495;
enum OBJ_dSAQuality = "OBJ_pilotAttributeType,49L";

enum LN_singleLevelQuality = "singleLevelQuality";
enum NID_singleLevelQuality = 496;
enum OBJ_singleLevelQuality = "OBJ_pilotAttributeType,50L";

enum LN_subtreeMinimumQuality = "subtreeMinimumQuality";
enum NID_subtreeMinimumQuality = 497;
enum OBJ_subtreeMinimumQuality = "OBJ_pilotAttributeType,51L";

enum LN_subtreeMaximumQuality = "subtreeMaximumQuality";
enum NID_subtreeMaximumQuality = 498;
enum OBJ_subtreeMaximumQuality = "OBJ_pilotAttributeType,52L";

enum LN_personalSignature = "personalSignature";
enum NID_personalSignature = 499;
enum OBJ_personalSignature = "OBJ_pilotAttributeType,53L";

enum LN_dITRedirect = "dITRedirect";
enum NID_dITRedirect = 500;
enum OBJ_dITRedirect = "OBJ_pilotAttributeType,54L";

enum SN_audio = "audio";
enum NID_audio = 501;
enum OBJ_audio = "OBJ_pilotAttributeType,55L";

enum LN_documentPublisher = "documentPublisher";
enum NID_documentPublisher = 502;
enum OBJ_documentPublisher = "OBJ_pilotAttributeType,56L";

enum SN_id_set = "id-set";
enum LN_id_set = "Secure Electronic Transactions";
enum NID_id_set = 512;
enum OBJ_id_set = "OBJ_international_organizations,42L";

enum SN_set_ctype = "set-ctype";
enum LN_set_ctype = "content types";
enum NID_set_ctype = 513;
enum OBJ_set_ctype = "OBJ_id_set,0L";

enum SN_set_msgExt = "set-msgExt";
enum LN_set_msgExt = "message extensions";
enum NID_set_msgExt = 514;
enum OBJ_set_msgExt = "OBJ_id_set,1L";

enum SN_set_attr = "set-attr";
enum NID_set_attr = 515;
enum OBJ_set_attr = "OBJ_id_set,3L";

enum SN_set_policy = "set-policy";
enum NID_set_policy = 516;
enum OBJ_set_policy = "OBJ_id_set,5L";

enum SN_set_certExt = "set-certExt";
enum LN_set_certExt = "certificate extensions";
enum NID_set_certExt = 517;
enum OBJ_set_certExt = "OBJ_id_set,7L";

enum SN_set_brand = "set-brand";
enum NID_set_brand = 518;
enum OBJ_set_brand = "OBJ_id_set,8L";

enum SN_setct_PANData = "setct-PANData";
enum NID_setct_PANData = 519;
enum OBJ_setct_PANData = "OBJ_set_ctype,0L";

enum SN_setct_PANToken = "setct-PANToken";
enum NID_setct_PANToken = 520;
enum OBJ_setct_PANToken = "OBJ_set_ctype,1L";

enum SN_setct_PANOnly = "setct-PANOnly";
enum NID_setct_PANOnly = 521;
enum OBJ_setct_PANOnly = "OBJ_set_ctype,2L";

enum SN_setct_OIData = "setct-OIData";
enum NID_setct_OIData = 522;
enum OBJ_setct_OIData = "OBJ_set_ctype,3L";

enum SN_setct_PI = "setct-PI";
enum NID_setct_PI = 523;
enum OBJ_setct_PI = "OBJ_set_ctype,4L";

enum SN_setct_PIData = "setct-PIData";
enum NID_setct_PIData = 524;
enum OBJ_setct_PIData = "OBJ_set_ctype,5L";

enum SN_setct_PIDataUnsigned = "setct-PIDataUnsigned";
enum NID_setct_PIDataUnsigned = 525;
enum OBJ_setct_PIDataUnsigned = "OBJ_set_ctype,6L";

enum SN_setct_HODInput = "setct-HODInput";
enum NID_setct_HODInput = 526;
enum OBJ_setct_HODInput = "OBJ_set_ctype,7L";

enum SN_setct_AuthResBaggage = "setct-AuthResBaggage";
enum NID_setct_AuthResBaggage = 527;
enum OBJ_setct_AuthResBaggage = "OBJ_set_ctype,8L";

enum SN_setct_AuthRevReqBaggage = "setct-AuthRevReqBaggage";
enum NID_setct_AuthRevReqBaggage = 528;
enum OBJ_setct_AuthRevReqBaggage = "OBJ_set_ctype,9L";

enum SN_setct_AuthRevResBaggage = "setct-AuthRevResBaggage";
enum NID_setct_AuthRevResBaggage = 529;
enum OBJ_setct_AuthRevResBaggage = "OBJ_set_ctype,10L";

enum SN_setct_CapTokenSeq = "setct-CapTokenSeq";
enum NID_setct_CapTokenSeq = 530;
enum OBJ_setct_CapTokenSeq = "OBJ_set_ctype,11L";

enum SN_setct_PInitResData = "setct-PInitResData";
enum NID_setct_PInitResData = 531;
enum OBJ_setct_PInitResData = "OBJ_set_ctype,12L";

enum SN_setct_PI_TBS = "setct-PI-TBS";
enum NID_setct_PI_TBS = 532;
enum OBJ_setct_PI_TBS = "OBJ_set_ctype,13L";

enum SN_setct_PResData = "setct-PResData";
enum NID_setct_PResData = 533;
enum OBJ_setct_PResData = "OBJ_set_ctype,14L";

enum SN_setct_AuthReqTBS = "setct-AuthReqTBS";
enum NID_setct_AuthReqTBS = 534;
enum OBJ_setct_AuthReqTBS = "OBJ_set_ctype,16L";

enum SN_setct_AuthResTBS = "setct-AuthResTBS";
enum NID_setct_AuthResTBS = 535;
enum OBJ_setct_AuthResTBS = "OBJ_set_ctype,17L";

enum SN_setct_AuthResTBSX = "setct-AuthResTBSX";
enum NID_setct_AuthResTBSX = 536;
enum OBJ_setct_AuthResTBSX = "OBJ_set_ctype,18L";

enum SN_setct_AuthTokenTBS = "setct-AuthTokenTBS";
enum NID_setct_AuthTokenTBS = 537;
enum OBJ_setct_AuthTokenTBS = "OBJ_set_ctype,19L";

enum SN_setct_CapTokenData = "setct-CapTokenData";
enum NID_setct_CapTokenData = 538;
enum OBJ_setct_CapTokenData = "OBJ_set_ctype,20L";

enum SN_setct_CapTokenTBS = "setct-CapTokenTBS";
enum NID_setct_CapTokenTBS = 539;
enum OBJ_setct_CapTokenTBS = "OBJ_set_ctype,21L";

enum SN_setct_AcqCardCodeMsg = "setct-AcqCardCodeMsg";
enum NID_setct_AcqCardCodeMsg = 540;
enum OBJ_setct_AcqCardCodeMsg = "OBJ_set_ctype,22L";

enum SN_setct_AuthRevReqTBS = "setct-AuthRevReqTBS";
enum NID_setct_AuthRevReqTBS = 541;
enum OBJ_setct_AuthRevReqTBS = "OBJ_set_ctype,23L";

enum SN_setct_AuthRevResData = "setct-AuthRevResData";
enum NID_setct_AuthRevResData = 542;
enum OBJ_setct_AuthRevResData = "OBJ_set_ctype,24L";

enum SN_setct_AuthRevResTBS = "setct-AuthRevResTBS";
enum NID_setct_AuthRevResTBS = 543;
enum OBJ_setct_AuthRevResTBS = "OBJ_set_ctype,25L";

enum SN_setct_CapReqTBS = "setct-CapReqTBS";
enum NID_setct_CapReqTBS = 544;
enum OBJ_setct_CapReqTBS = "OBJ_set_ctype,26L";

enum SN_setct_CapReqTBSX = "setct-CapReqTBSX";
enum NID_setct_CapReqTBSX = 545;
enum OBJ_setct_CapReqTBSX = "OBJ_set_ctype,27L";

enum SN_setct_CapResData = "setct-CapResData";
enum NID_setct_CapResData = 546;
enum OBJ_setct_CapResData = "OBJ_set_ctype,28L";

enum SN_setct_CapRevReqTBS = "setct-CapRevReqTBS";
enum NID_setct_CapRevReqTBS = 547;
enum OBJ_setct_CapRevReqTBS = "OBJ_set_ctype,29L";

enum SN_setct_CapRevReqTBSX = "setct-CapRevReqTBSX";
enum NID_setct_CapRevReqTBSX = 548;
enum OBJ_setct_CapRevReqTBSX = "OBJ_set_ctype,30L";

enum SN_setct_CapRevResData = "setct-CapRevResData";
enum NID_setct_CapRevResData = 549;
enum OBJ_setct_CapRevResData = "OBJ_set_ctype,31L";

enum SN_setct_CredReqTBS = "setct-CredReqTBS";
enum NID_setct_CredReqTBS = 550;
enum OBJ_setct_CredReqTBS = "OBJ_set_ctype,32L";

enum SN_setct_CredReqTBSX = "setct-CredReqTBSX";
enum NID_setct_CredReqTBSX = 551;
enum OBJ_setct_CredReqTBSX = "OBJ_set_ctype,33L";

enum SN_setct_CredResData = "setct-CredResData";
enum NID_setct_CredResData = 552;
enum OBJ_setct_CredResData = "OBJ_set_ctype,34L";

enum SN_setct_CredRevReqTBS = "setct-CredRevReqTBS";
enum NID_setct_CredRevReqTBS = 553;
enum OBJ_setct_CredRevReqTBS = "OBJ_set_ctype,35L";

enum SN_setct_CredRevReqTBSX = "setct-CredRevReqTBSX";
enum NID_setct_CredRevReqTBSX = 554;
enum OBJ_setct_CredRevReqTBSX = "OBJ_set_ctype,36L";

enum SN_setct_CredRevResData = "setct-CredRevResData";
enum NID_setct_CredRevResData = 555;
enum OBJ_setct_CredRevResData = "OBJ_set_ctype,37L";

enum SN_setct_PCertReqData = "setct-PCertReqData";
enum NID_setct_PCertReqData = 556;
enum OBJ_setct_PCertReqData = "OBJ_set_ctype,38L";

enum SN_setct_PCertResTBS = "setct-PCertResTBS";
enum NID_setct_PCertResTBS = 557;
enum OBJ_setct_PCertResTBS = "OBJ_set_ctype,39L";

enum SN_setct_BatchAdminReqData = "setct-BatchAdminReqData";
enum NID_setct_BatchAdminReqData = 558;
enum OBJ_setct_BatchAdminReqData = "OBJ_set_ctype,40L";

enum SN_setct_BatchAdminResData = "setct-BatchAdminResData";
enum NID_setct_BatchAdminResData = 559;
enum OBJ_setct_BatchAdminResData = "OBJ_set_ctype,41L";

enum SN_setct_CardCInitResTBS = "setct-CardCInitResTBS";
enum NID_setct_CardCInitResTBS = 560;
enum OBJ_setct_CardCInitResTBS = "OBJ_set_ctype,42L";

enum SN_setct_MeAqCInitResTBS = "setct-MeAqCInitResTBS";
enum NID_setct_MeAqCInitResTBS = 561;
enum OBJ_setct_MeAqCInitResTBS = "OBJ_set_ctype,43L";

enum SN_setct_RegFormResTBS = "setct-RegFormResTBS";
enum NID_setct_RegFormResTBS = 562;
enum OBJ_setct_RegFormResTBS = "OBJ_set_ctype,44L";

enum SN_setct_CertReqData = "setct-CertReqData";
enum NID_setct_CertReqData = 563;
enum OBJ_setct_CertReqData = "OBJ_set_ctype,45L";

enum SN_setct_CertReqTBS = "setct-CertReqTBS";
enum NID_setct_CertReqTBS = 564;
enum OBJ_setct_CertReqTBS = "OBJ_set_ctype,46L";

enum SN_setct_CertResData = "setct-CertResData";
enum NID_setct_CertResData = 565;
enum OBJ_setct_CertResData = "OBJ_set_ctype,47L";

enum SN_setct_CertInqReqTBS = "setct-CertInqReqTBS";
enum NID_setct_CertInqReqTBS = 566;
enum OBJ_setct_CertInqReqTBS = "OBJ_set_ctype,48L";

enum SN_setct_ErrorTBS = "setct-ErrorTBS";
enum NID_setct_ErrorTBS = 567;
enum OBJ_setct_ErrorTBS = "OBJ_set_ctype,49L";

enum SN_setct_PIDualSignedTBE = "setct-PIDualSignedTBE";
enum NID_setct_PIDualSignedTBE = 568;
enum OBJ_setct_PIDualSignedTBE = "OBJ_set_ctype,50L";

enum SN_setct_PIUnsignedTBE = "setct-PIUnsignedTBE";
enum NID_setct_PIUnsignedTBE = 569;
enum OBJ_setct_PIUnsignedTBE = "OBJ_set_ctype,51L";

enum SN_setct_AuthReqTBE = "setct-AuthReqTBE";
enum NID_setct_AuthReqTBE = 570;
enum OBJ_setct_AuthReqTBE = "OBJ_set_ctype,52L";

enum SN_setct_AuthResTBE = "setct-AuthResTBE";
enum NID_setct_AuthResTBE = 571;
enum OBJ_setct_AuthResTBE = "OBJ_set_ctype,53L";

enum SN_setct_AuthResTBEX = "setct-AuthResTBEX";
enum NID_setct_AuthResTBEX = 572;
enum OBJ_setct_AuthResTBEX = "OBJ_set_ctype,54L";

enum SN_setct_AuthTokenTBE = "setct-AuthTokenTBE";
enum NID_setct_AuthTokenTBE = 573;
enum OBJ_setct_AuthTokenTBE = "OBJ_set_ctype,55L";

enum SN_setct_CapTokenTBE = "setct-CapTokenTBE";
enum NID_setct_CapTokenTBE = 574;
enum OBJ_setct_CapTokenTBE = "OBJ_set_ctype,56L";

enum SN_setct_CapTokenTBEX = "setct-CapTokenTBEX";
enum NID_setct_CapTokenTBEX = 575;
enum OBJ_setct_CapTokenTBEX = "OBJ_set_ctype,57L";

enum SN_setct_AcqCardCodeMsgTBE = "setct-AcqCardCodeMsgTBE";
enum NID_setct_AcqCardCodeMsgTBE = 576;
enum OBJ_setct_AcqCardCodeMsgTBE = "OBJ_set_ctype,58L";

enum SN_setct_AuthRevReqTBE = "setct-AuthRevReqTBE";
enum NID_setct_AuthRevReqTBE = 577;
enum OBJ_setct_AuthRevReqTBE = "OBJ_set_ctype,59L";

enum SN_setct_AuthRevResTBE = "setct-AuthRevResTBE";
enum NID_setct_AuthRevResTBE = 578;
enum OBJ_setct_AuthRevResTBE = "OBJ_set_ctype,60L";

enum SN_setct_AuthRevResTBEB = "setct-AuthRevResTBEB";
enum NID_setct_AuthRevResTBEB = 579;
enum OBJ_setct_AuthRevResTBEB = "OBJ_set_ctype,61L";

enum SN_setct_CapReqTBE = "setct-CapReqTBE";
enum NID_setct_CapReqTBE = 580;
enum OBJ_setct_CapReqTBE = "OBJ_set_ctype,62L";

enum SN_setct_CapReqTBEX = "setct-CapReqTBEX";
enum NID_setct_CapReqTBEX = 581;
enum OBJ_setct_CapReqTBEX = "OBJ_set_ctype,63L";

enum SN_setct_CapResTBE = "setct-CapResTBE";
enum NID_setct_CapResTBE = 582;
enum OBJ_setct_CapResTBE = "OBJ_set_ctype,64L";

enum SN_setct_CapRevReqTBE = "setct-CapRevReqTBE";
enum NID_setct_CapRevReqTBE = 583;
enum OBJ_setct_CapRevReqTBE = "OBJ_set_ctype,65L";

enum SN_setct_CapRevReqTBEX = "setct-CapRevReqTBEX";
enum NID_setct_CapRevReqTBEX = 584;
enum OBJ_setct_CapRevReqTBEX = "OBJ_set_ctype,66L";

enum SN_setct_CapRevResTBE = "setct-CapRevResTBE";
enum NID_setct_CapRevResTBE = 585;
enum OBJ_setct_CapRevResTBE = "OBJ_set_ctype,67L";

enum SN_setct_CredReqTBE = "setct-CredReqTBE";
enum NID_setct_CredReqTBE = 586;
enum OBJ_setct_CredReqTBE = "OBJ_set_ctype,68L";

enum SN_setct_CredReqTBEX = "setct-CredReqTBEX";
enum NID_setct_CredReqTBEX = 587;
enum OBJ_setct_CredReqTBEX = "OBJ_set_ctype,69L";

enum SN_setct_CredResTBE = "setct-CredResTBE";
enum NID_setct_CredResTBE = 588;
enum OBJ_setct_CredResTBE = "OBJ_set_ctype,70L";

enum SN_setct_CredRevReqTBE = "setct-CredRevReqTBE";
enum NID_setct_CredRevReqTBE = 589;
enum OBJ_setct_CredRevReqTBE = "OBJ_set_ctype,71L";

enum SN_setct_CredRevReqTBEX = "setct-CredRevReqTBEX";
enum NID_setct_CredRevReqTBEX = 590;
enum OBJ_setct_CredRevReqTBEX = "OBJ_set_ctype,72L";

enum SN_setct_CredRevResTBE = "setct-CredRevResTBE";
enum NID_setct_CredRevResTBE = 591;
enum OBJ_setct_CredRevResTBE = "OBJ_set_ctype,73L";

enum SN_setct_BatchAdminReqTBE = "setct-BatchAdminReqTBE";
enum NID_setct_BatchAdminReqTBE = 592;
enum OBJ_setct_BatchAdminReqTBE = "OBJ_set_ctype,74L";

enum SN_setct_BatchAdminResTBE = "setct-BatchAdminResTBE";
enum NID_setct_BatchAdminResTBE = 593;
enum OBJ_setct_BatchAdminResTBE = "OBJ_set_ctype,75L";

enum SN_setct_RegFormReqTBE = "setct-RegFormReqTBE";
enum NID_setct_RegFormReqTBE = 594;
enum OBJ_setct_RegFormReqTBE = "OBJ_set_ctype,76L";

enum SN_setct_CertReqTBE = "setct-CertReqTBE";
enum NID_setct_CertReqTBE = 595;
enum OBJ_setct_CertReqTBE = "OBJ_set_ctype,77L";

enum SN_setct_CertReqTBEX = "setct-CertReqTBEX";
enum NID_setct_CertReqTBEX = 596;
enum OBJ_setct_CertReqTBEX = "OBJ_set_ctype,78L";

enum SN_setct_CertResTBE = "setct-CertResTBE";
enum NID_setct_CertResTBE = 597;
enum OBJ_setct_CertResTBE = "OBJ_set_ctype,79L";

enum SN_setct_CRLNotificationTBS = "setct-CRLNotificationTBS";
enum NID_setct_CRLNotificationTBS = 598;
enum OBJ_setct_CRLNotificationTBS = "OBJ_set_ctype,80L";

enum SN_setct_CRLNotificationResTBS = "setct-CRLNotificationResTBS";
enum NID_setct_CRLNotificationResTBS = 599;
enum OBJ_setct_CRLNotificationResTBS = "OBJ_set_ctype,81L";

enum SN_setct_BCIDistributionTBS = "setct-BCIDistributionTBS";
enum NID_setct_BCIDistributionTBS = 600;
enum OBJ_setct_BCIDistributionTBS = "OBJ_set_ctype,82L";

enum SN_setext_genCrypt = "setext-genCrypt";
enum LN_setext_genCrypt = "generic cryptogram";
enum NID_setext_genCrypt = 601;
enum OBJ_setext_genCrypt = "OBJ_set_msgExt,1L";

enum SN_setext_miAuth = "setext-miAuth";
enum LN_setext_miAuth = "merchant initiated auth";
enum NID_setext_miAuth = 602;
enum OBJ_setext_miAuth = "OBJ_set_msgExt,3L";

enum SN_setext_pinSecure = "setext-pinSecure";
enum NID_setext_pinSecure = 603;
enum OBJ_setext_pinSecure = "OBJ_set_msgExt,4L";

enum SN_setext_pinAny = "setext-pinAny";
enum NID_setext_pinAny = 604;
enum OBJ_setext_pinAny = "OBJ_set_msgExt,5L";

enum SN_setext_track2 = "setext-track2";
enum NID_setext_track2 = 605;
enum OBJ_setext_track2 = "OBJ_set_msgExt,7L";

enum SN_setext_cv = "setext-cv";
enum LN_setext_cv = "additional verification";
enum NID_setext_cv = 606;
enum OBJ_setext_cv = "OBJ_set_msgExt,8L";

enum SN_set_policy_root = "set-policy-root";
enum NID_set_policy_root = 607;
enum OBJ_set_policy_root = "OBJ_set_policy,0L";

enum SN_setCext_hashedRoot = "setCext-hashedRoot";
enum NID_setCext_hashedRoot = 608;
enum OBJ_setCext_hashedRoot = "OBJ_set_certExt,0L";

enum SN_setCext_certType = "setCext-certType";
enum NID_setCext_certType = 609;
enum OBJ_setCext_certType = "OBJ_set_certExt,1L";

enum SN_setCext_merchData = "setCext-merchData";
enum NID_setCext_merchData = 610;
enum OBJ_setCext_merchData = "OBJ_set_certExt,2L";

enum SN_setCext_cCertRequired = "setCext-cCertRequired";
enum NID_setCext_cCertRequired = 611;
enum OBJ_setCext_cCertRequired = "OBJ_set_certExt,3L";

enum SN_setCext_tunneling = "setCext-tunneling";
enum NID_setCext_tunneling = 612;
enum OBJ_setCext_tunneling = "OBJ_set_certExt,4L";

enum SN_setCext_setExt = "setCext-setExt";
enum NID_setCext_setExt = 613;
enum OBJ_setCext_setExt = "OBJ_set_certExt,5L";

enum SN_setCext_setQualf = "setCext-setQualf";
enum NID_setCext_setQualf = 614;
enum OBJ_setCext_setQualf = "OBJ_set_certExt,6L";

enum SN_setCext_PGWYcapabilities = "setCext-PGWYcapabilities";
enum NID_setCext_PGWYcapabilities = 615;
enum OBJ_setCext_PGWYcapabilities = "OBJ_set_certExt,7L";

enum SN_setCext_TokenIdentifier = "setCext-TokenIdentifier";
enum NID_setCext_TokenIdentifier = 616;
enum OBJ_setCext_TokenIdentifier = "OBJ_set_certExt,8L";

enum SN_setCext_Track2Data = "setCext-Track2Data";
enum NID_setCext_Track2Data = 617;
enum OBJ_setCext_Track2Data = "OBJ_set_certExt,9L";

enum SN_setCext_TokenType = "setCext-TokenType";
enum NID_setCext_TokenType = 618;
enum OBJ_setCext_TokenType = "OBJ_set_certExt,10L";

enum SN_setCext_IssuerCapabilities = "setCext-IssuerCapabilities";
enum NID_setCext_IssuerCapabilities = 619;
enum OBJ_setCext_IssuerCapabilities = "OBJ_set_certExt,11L";

enum SN_setAttr_Cert = "setAttr-Cert";
enum NID_setAttr_Cert = 620;
enum OBJ_setAttr_Cert = "OBJ_set_attr,0L";

enum SN_setAttr_PGWYcap = "setAttr-PGWYcap";
enum LN_setAttr_PGWYcap = "payment gateway capabilities";
enum NID_setAttr_PGWYcap = 621;
enum OBJ_setAttr_PGWYcap = "OBJ_set_attr,1L";

enum SN_setAttr_TokenType = "setAttr-TokenType";
enum NID_setAttr_TokenType = 622;
enum OBJ_setAttr_TokenType = "OBJ_set_attr,2L";

enum SN_setAttr_IssCap = "setAttr-IssCap";
enum LN_setAttr_IssCap = "issuer capabilities";
enum NID_setAttr_IssCap = 623;
enum OBJ_setAttr_IssCap = "OBJ_set_attr,3L";

enum SN_set_rootKeyThumb = "set-rootKeyThumb";
enum NID_set_rootKeyThumb = 624;
enum OBJ_set_rootKeyThumb = "OBJ_setAttr_Cert,0L";

enum SN_set_addPolicy = "set-addPolicy";
enum NID_set_addPolicy = 625;
enum OBJ_set_addPolicy = "OBJ_setAttr_Cert,1L";

enum SN_setAttr_Token_EMV = "setAttr-Token-EMV";
enum NID_setAttr_Token_EMV = 626;
enum OBJ_setAttr_Token_EMV = "OBJ_setAttr_TokenType,1L";

enum SN_setAttr_Token_B0Prime = "setAttr-Token-B0Prime";
enum NID_setAttr_Token_B0Prime = 627;
enum OBJ_setAttr_Token_B0Prime = "OBJ_setAttr_TokenType,2L";

enum SN_setAttr_IssCap_CVM = "setAttr-IssCap-CVM";
enum NID_setAttr_IssCap_CVM = 628;
enum OBJ_setAttr_IssCap_CVM = "OBJ_setAttr_IssCap,3L";

enum SN_setAttr_IssCap_T2 = "setAttr-IssCap-T2";
enum NID_setAttr_IssCap_T2 = 629;
enum OBJ_setAttr_IssCap_T2 = "OBJ_setAttr_IssCap,4L";

enum SN_setAttr_IssCap_Sig = "setAttr-IssCap-Sig";
enum NID_setAttr_IssCap_Sig = 630;
enum OBJ_setAttr_IssCap_Sig = "OBJ_setAttr_IssCap,5L";

enum SN_setAttr_GenCryptgrm = "setAttr-GenCryptgrm";
enum LN_setAttr_GenCryptgrm = "generate cryptogram";
enum NID_setAttr_GenCryptgrm = 631;
enum OBJ_setAttr_GenCryptgrm = "OBJ_setAttr_IssCap_CVM,1L";

enum SN_setAttr_T2Enc = "setAttr-T2Enc";
enum LN_setAttr_T2Enc = "encrypted track 2";
enum NID_setAttr_T2Enc = 632;
enum OBJ_setAttr_T2Enc = "OBJ_setAttr_IssCap_T2,1L";

enum SN_setAttr_T2cleartxt = "setAttr-T2cleartxt";
enum LN_setAttr_T2cleartxt = "cleartext track 2";
enum NID_setAttr_T2cleartxt = 633;
enum OBJ_setAttr_T2cleartxt = "OBJ_setAttr_IssCap_T2,2L";

enum SN_setAttr_TokICCsig = "setAttr-TokICCsig";
enum LN_setAttr_TokICCsig = "ICC or token signature";
enum NID_setAttr_TokICCsig = 634;
enum OBJ_setAttr_TokICCsig = "OBJ_setAttr_IssCap_Sig,1L";

enum SN_setAttr_SecDevSig = "setAttr-SecDevSig";
enum LN_setAttr_SecDevSig = "secure device signature";
enum NID_setAttr_SecDevSig = 635;
enum OBJ_setAttr_SecDevSig = "OBJ_setAttr_IssCap_Sig,2L";

enum SN_set_brand_IATA_ATA = "set-brand-IATA-ATA";
enum NID_set_brand_IATA_ATA = 636;
enum OBJ_set_brand_IATA_ATA = "OBJ_set_brand,1L";

enum SN_set_brand_Diners = "set-brand-Diners";
enum NID_set_brand_Diners = 637;
enum OBJ_set_brand_Diners = "OBJ_set_brand,30L";

enum SN_set_brand_AmericanExpress = "set-brand-AmericanExpress";
enum NID_set_brand_AmericanExpress = 638;
enum OBJ_set_brand_AmericanExpress = "OBJ_set_brand,34L";

enum SN_set_brand_JCB = "set-brand-JCB";
enum NID_set_brand_JCB = 639;
enum OBJ_set_brand_JCB = "OBJ_set_brand,35L";

enum SN_set_brand_Visa = "set-brand-Visa";
enum NID_set_brand_Visa = 640;
enum OBJ_set_brand_Visa = "OBJ_set_brand,4L";

enum SN_set_brand_MasterCard = "set-brand-MasterCard";
enum NID_set_brand_MasterCard = 641;
enum OBJ_set_brand_MasterCard = "OBJ_set_brand,5L";

enum SN_set_brand_Novus = "set-brand-Novus";
enum NID_set_brand_Novus = 642;
enum OBJ_set_brand_Novus = "OBJ_set_brand,6011L";

enum SN_des_cdmf = "DES-CDMF";
enum LN_des_cdmf = "des-cdmf";
enum NID_des_cdmf = 643;
enum OBJ_des_cdmf = "OBJ_rsadsi,3L,10L";

enum SN_rsaOAEPEncryptionSET = "rsaOAEPEncryptionSET";
enum NID_rsaOAEPEncryptionSET = 644;
enum OBJ_rsaOAEPEncryptionSET = "OBJ_rsadsi,1L,1L,6L";

enum SN_ipsec3 = "Oakley-EC2N-3";
enum LN_ipsec3 = "ipsec3";
enum NID_ipsec3 = 749;

enum SN_ipsec4 = "Oakley-EC2N-4";
enum LN_ipsec4 = "ipsec4";
enum NID_ipsec4 = 750;

enum SN_whirlpool = "whirlpool";
enum NID_whirlpool = 804;
enum OBJ_whirlpool = "OBJ_iso,0L,10118L,3L,0L,55L";

enum SN_cryptopro = "cryptopro";
enum NID_cryptopro = 805;
enum OBJ_cryptopro = "OBJ_member_body,643L,2L,2L";

enum SN_cryptocom = "cryptocom";
enum NID_cryptocom = 806;
enum OBJ_cryptocom = "OBJ_member_body,643L,2L,9L";

enum SN_id_GostR3411_94_with_GostR3410_2001 = "id-GostR3411-94-with-GostR3410-2001";
enum LN_id_GostR3411_94_with_GostR3410_2001 = "GOST R 34.11-94 with GOST R 34.10-2001";
enum NID_id_GostR3411_94_with_GostR3410_2001 = 807;
enum OBJ_id_GostR3411_94_with_GostR3410_2001 = "OBJ_cryptopro,3L";

enum SN_id_GostR3411_94_with_GostR3410_94 = "id-GostR3411-94-with-GostR3410-94";
enum LN_id_GostR3411_94_with_GostR3410_94 = "GOST R 34.11-94 with GOST R 34.10-94";
enum NID_id_GostR3411_94_with_GostR3410_94 = 808;
enum OBJ_id_GostR3411_94_with_GostR3410_94 = "OBJ_cryptopro,4L";

enum SN_id_GostR3411_94 = "md_gost94";
enum LN_id_GostR3411_94 = "GOST R 34.11-94";
enum NID_id_GostR3411_94 = 809;
enum OBJ_id_GostR3411_94 = "OBJ_cryptopro,9L";

enum SN_id_HMACGostR3411_94 = "id-HMACGostR3411-94";
enum LN_id_HMACGostR3411_94 = "HMAC GOST 34.11-94";
enum NID_id_HMACGostR3411_94 = 810;
enum OBJ_id_HMACGostR3411_94 = "OBJ_cryptopro,10L";

enum SN_id_GostR3410_2001 = "gost2001";
enum LN_id_GostR3410_2001 = "GOST R 34.10-2001";
enum NID_id_GostR3410_2001 = 811;
enum OBJ_id_GostR3410_2001 = "OBJ_cryptopro,19L";

enum SN_id_GostR3410_94 = "gost94";
enum LN_id_GostR3410_94 = "GOST R 34.10-94";
enum NID_id_GostR3410_94 = 812;
enum OBJ_id_GostR3410_94 = "OBJ_cryptopro,20L";

enum SN_id_Gost28147_89 = "gost89";
enum LN_id_Gost28147_89 = "GOST 28147-89";
enum NID_id_Gost28147_89 = 813;
enum OBJ_id_Gost28147_89 = "OBJ_cryptopro,21L";

enum SN_gost89_cnt = "gost89-cnt";
enum NID_gost89_cnt = 814;

enum SN_id_Gost28147_89_MAC = "gost-mac";
enum LN_id_Gost28147_89_MAC = "GOST 28147-89 MAC";
enum NID_id_Gost28147_89_MAC = 815;
enum OBJ_id_Gost28147_89_MAC = "OBJ_cryptopro,22L";

enum SN_id_GostR3411_94_prf = "prf-gostr3411-94";
enum LN_id_GostR3411_94_prf = "GOST R 34.11-94 PRF";
enum NID_id_GostR3411_94_prf = 816;
enum OBJ_id_GostR3411_94_prf = "OBJ_cryptopro,23L";

enum SN_id_GostR3410_2001DH = "id-GostR3410-2001DH";
enum LN_id_GostR3410_2001DH = "GOST R 34.10-2001 DH";
enum NID_id_GostR3410_2001DH = 817;
enum OBJ_id_GostR3410_2001DH = "OBJ_cryptopro,98L";

enum SN_id_GostR3410_94DH = "id-GostR3410-94DH";
enum LN_id_GostR3410_94DH = "GOST R 34.10-94 DH";
enum NID_id_GostR3410_94DH = 818;
enum OBJ_id_GostR3410_94DH = "OBJ_cryptopro,99L";

enum SN_id_Gost28147_89_CryptoPro_KeyMeshing = "id-Gost28147-89-CryptoPro-KeyMeshing";
enum NID_id_Gost28147_89_CryptoPro_KeyMeshing = 819;
enum OBJ_id_Gost28147_89_CryptoPro_KeyMeshing = "OBJ_cryptopro,14L,1L";

enum SN_id_Gost28147_89_None_KeyMeshing = "id-Gost28147-89-None-KeyMeshing";
enum NID_id_Gost28147_89_None_KeyMeshing = 820;
enum OBJ_id_Gost28147_89_None_KeyMeshing = "OBJ_cryptopro,14L,0L";

enum SN_id_GostR3411_94_TestParamSet = "id-GostR3411-94-TestParamSet";
enum NID_id_GostR3411_94_TestParamSet = 821;
enum OBJ_id_GostR3411_94_TestParamSet = "OBJ_cryptopro,30L,0L";

enum SN_id_GostR3411_94_CryptoProParamSet = "id-GostR3411-94-CryptoProParamSet";
enum NID_id_GostR3411_94_CryptoProParamSet = 822;
enum OBJ_id_GostR3411_94_CryptoProParamSet = "OBJ_cryptopro,30L,1L";

enum SN_id_Gost28147_89_TestParamSet = "id-Gost28147-89-TestParamSet";
enum NID_id_Gost28147_89_TestParamSet = 823;
enum OBJ_id_Gost28147_89_TestParamSet = "OBJ_cryptopro,31L,0L";

enum SN_id_Gost28147_89_CryptoPro_A_ParamSet = "id-Gost28147-89-CryptoPro-A-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_A_ParamSet = 824;
enum OBJ_id_Gost28147_89_CryptoPro_A_ParamSet = "OBJ_cryptopro,31L,1L";

enum SN_id_Gost28147_89_CryptoPro_B_ParamSet = "id-Gost28147-89-CryptoPro-B-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_B_ParamSet = 825;
enum OBJ_id_Gost28147_89_CryptoPro_B_ParamSet = "OBJ_cryptopro,31L,2L";

enum SN_id_Gost28147_89_CryptoPro_C_ParamSet = "id-Gost28147-89-CryptoPro-C-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_C_ParamSet = 826;
enum OBJ_id_Gost28147_89_CryptoPro_C_ParamSet = "OBJ_cryptopro,31L,3L";

enum SN_id_Gost28147_89_CryptoPro_D_ParamSet = "id-Gost28147-89-CryptoPro-D-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_D_ParamSet = 827;
enum OBJ_id_Gost28147_89_CryptoPro_D_ParamSet = "OBJ_cryptopro,31L,4L";

enum SN_id_Gost28147_89_CryptoPro_Oscar_1_1_ParamSet = "id-Gost28147-89-CryptoPro-Oscar-1-1-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_Oscar_1_1_ParamSet = 828;
enum OBJ_id_Gost28147_89_CryptoPro_Oscar_1_1_ParamSet = "OBJ_cryptopro,31L,5L";

enum SN_id_Gost28147_89_CryptoPro_Oscar_1_0_ParamSet = "id-Gost28147-89-CryptoPro-Oscar-1-0-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_Oscar_1_0_ParamSet = 829;
enum OBJ_id_Gost28147_89_CryptoPro_Oscar_1_0_ParamSet = "OBJ_cryptopro,31L,6L";

enum SN_id_Gost28147_89_CryptoPro_RIC_1_ParamSet = "id-Gost28147-89-CryptoPro-RIC-1-ParamSet";
enum NID_id_Gost28147_89_CryptoPro_RIC_1_ParamSet = 830;
enum OBJ_id_Gost28147_89_CryptoPro_RIC_1_ParamSet = "OBJ_cryptopro,31L,7L";

enum SN_id_GostR3410_94_TestParamSet = "id-GostR3410-94-TestParamSet";
enum NID_id_GostR3410_94_TestParamSet = 831;
enum OBJ_id_GostR3410_94_TestParamSet = "OBJ_cryptopro,32L,0L";

enum SN_id_GostR3410_94_CryptoPro_A_ParamSet = "id-GostR3410-94-CryptoPro-A-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_A_ParamSet = 832;
enum OBJ_id_GostR3410_94_CryptoPro_A_ParamSet = "OBJ_cryptopro,32L,2L";

enum SN_id_GostR3410_94_CryptoPro_B_ParamSet = "id-GostR3410-94-CryptoPro-B-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_B_ParamSet = 833;
enum OBJ_id_GostR3410_94_CryptoPro_B_ParamSet = "OBJ_cryptopro,32L,3L";

enum SN_id_GostR3410_94_CryptoPro_C_ParamSet = "id-GostR3410-94-CryptoPro-C-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_C_ParamSet = 834;
enum OBJ_id_GostR3410_94_CryptoPro_C_ParamSet = "OBJ_cryptopro,32L,4L";

enum SN_id_GostR3410_94_CryptoPro_D_ParamSet = "id-GostR3410-94-CryptoPro-D-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_D_ParamSet = 835;
enum OBJ_id_GostR3410_94_CryptoPro_D_ParamSet = "OBJ_cryptopro,32L,5L";

enum SN_id_GostR3410_94_CryptoPro_XchA_ParamSet = "id-GostR3410-94-CryptoPro-XchA-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_XchA_ParamSet = 836;
enum OBJ_id_GostR3410_94_CryptoPro_XchA_ParamSet = "OBJ_cryptopro,33L,1L";

enum SN_id_GostR3410_94_CryptoPro_XchB_ParamSet = "id-GostR3410-94-CryptoPro-XchB-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_XchB_ParamSet = 837;
enum OBJ_id_GostR3410_94_CryptoPro_XchB_ParamSet = "OBJ_cryptopro,33L,2L";

enum SN_id_GostR3410_94_CryptoPro_XchC_ParamSet = "id-GostR3410-94-CryptoPro-XchC-ParamSet";
enum NID_id_GostR3410_94_CryptoPro_XchC_ParamSet = 838;
enum OBJ_id_GostR3410_94_CryptoPro_XchC_ParamSet = "OBJ_cryptopro,33L,3L";

enum SN_id_GostR3410_2001_TestParamSet = "id-GostR3410-2001-TestParamSet";
enum NID_id_GostR3410_2001_TestParamSet = 839;
enum OBJ_id_GostR3410_2001_TestParamSet = "OBJ_cryptopro,35L,0L";

enum SN_id_GostR3410_2001_CryptoPro_A_ParamSet = "id-GostR3410-2001-CryptoPro-A-ParamSet";
enum NID_id_GostR3410_2001_CryptoPro_A_ParamSet = 840;
enum OBJ_id_GostR3410_2001_CryptoPro_A_ParamSet = "OBJ_cryptopro,35L,1L";

enum SN_id_GostR3410_2001_CryptoPro_B_ParamSet = "id-GostR3410-2001-CryptoPro-B-ParamSet";
enum NID_id_GostR3410_2001_CryptoPro_B_ParamSet = 841;
enum OBJ_id_GostR3410_2001_CryptoPro_B_ParamSet = "OBJ_cryptopro,35L,2L";

enum SN_id_GostR3410_2001_CryptoPro_C_ParamSet = "id-GostR3410-2001-CryptoPro-C-ParamSet";
enum NID_id_GostR3410_2001_CryptoPro_C_ParamSet = 842;
enum OBJ_id_GostR3410_2001_CryptoPro_C_ParamSet = "OBJ_cryptopro,35L,3L";

enum SN_id_GostR3410_2001_CryptoPro_XchA_ParamSet = "id-GostR3410-2001-CryptoPro-XchA-ParamSet";
enum NID_id_GostR3410_2001_CryptoPro_XchA_ParamSet = 843;
enum OBJ_id_GostR3410_2001_CryptoPro_XchA_ParamSet = "OBJ_cryptopro,36L,0L";

enum SN_id_GostR3410_2001_CryptoPro_XchB_ParamSet = "id-GostR3410-2001-CryptoPro-XchB-ParamSet";
enum NID_id_GostR3410_2001_CryptoPro_XchB_ParamSet = 844;
enum OBJ_id_GostR3410_2001_CryptoPro_XchB_ParamSet = "OBJ_cryptopro,36L,1L";

enum SN_id_GostR3410_94_a = "id-GostR3410-94-a";
enum NID_id_GostR3410_94_a = 845;
enum OBJ_id_GostR3410_94_a = "OBJ_id_GostR3410_94,1L";

enum SN_id_GostR3410_94_aBis = "id-GostR3410-94-aBis";
enum NID_id_GostR3410_94_aBis = 846;
enum OBJ_id_GostR3410_94_aBis = "OBJ_id_GostR3410_94,2L";

enum SN_id_GostR3410_94_b = "id-GostR3410-94-b";
enum NID_id_GostR3410_94_b = 847;
enum OBJ_id_GostR3410_94_b = "OBJ_id_GostR3410_94,3L";

enum SN_id_GostR3410_94_bBis = "id-GostR3410-94-bBis";
enum NID_id_GostR3410_94_bBis = 848;
enum OBJ_id_GostR3410_94_bBis = "OBJ_id_GostR3410_94,4L";

enum SN_id_Gost28147_89_cc = "id-Gost28147-89-cc";
enum LN_id_Gost28147_89_cc = "GOST 28147-89 Cryptocom ParamSet";
enum NID_id_Gost28147_89_cc = 849;
enum OBJ_id_Gost28147_89_cc = "OBJ_cryptocom,1L,6L,1L";

enum SN_id_GostR3410_94_cc = "gost94cc";
enum LN_id_GostR3410_94_cc = "GOST 34.10-94 Cryptocom";
enum NID_id_GostR3410_94_cc = 850;
enum OBJ_id_GostR3410_94_cc = "OBJ_cryptocom,1L,5L,3L";

enum SN_id_GostR3410_2001_cc = "gost2001cc";
enum LN_id_GostR3410_2001_cc = "GOST 34.10-2001 Cryptocom";
enum NID_id_GostR3410_2001_cc = 851;
enum OBJ_id_GostR3410_2001_cc = "OBJ_cryptocom,1L,5L,4L";

enum SN_id_GostR3411_94_with_GostR3410_94_cc = "id-GostR3411-94-with-GostR3410-94-cc";
enum LN_id_GostR3411_94_with_GostR3410_94_cc = "GOST R 34.11-94 with GOST R 34.10-94 Cryptocom";
enum NID_id_GostR3411_94_with_GostR3410_94_cc = 852;
enum OBJ_id_GostR3411_94_with_GostR3410_94_cc = "OBJ_cryptocom,1L,3L,3L";

enum SN_id_GostR3411_94_with_GostR3410_2001_cc = "id-GostR3411-94-with-GostR3410-2001-cc";
enum LN_id_GostR3411_94_with_GostR3410_2001_cc = "GOST R 34.11-94 with GOST R 34.10-2001 Cryptocom";
enum NID_id_GostR3411_94_with_GostR3410_2001_cc = 853;
enum OBJ_id_GostR3411_94_with_GostR3410_2001_cc = "OBJ_cryptocom,1L,3L,4L";

enum SN_id_GostR3410_2001_ParamSet_cc = "id-GostR3410-2001-ParamSet-cc";
enum LN_id_GostR3410_2001_ParamSet_cc = "GOST R 3410-2001 Parameter Set Cryptocom";
enum NID_id_GostR3410_2001_ParamSet_cc = 854;
enum OBJ_id_GostR3410_2001_ParamSet_cc = "OBJ_cryptocom,1L,8L,1L";

enum SN_camellia_128_cbc = "CAMELLIA-128-CBC";
enum LN_camellia_128_cbc = "camellia-128-cbc";
enum NID_camellia_128_cbc = 751;
enum OBJ_camellia_128_cbc = "1L,2L,392L,200011L,61L,1L,1L,1L,2L";

enum SN_camellia_192_cbc = "CAMELLIA-192-CBC";
enum LN_camellia_192_cbc = "camellia-192-cbc";
enum NID_camellia_192_cbc = 752;
enum OBJ_camellia_192_cbc = "1L,2L,392L,200011L,61L,1L,1L,1L,3L";

enum SN_camellia_256_cbc = "CAMELLIA-256-CBC";
enum LN_camellia_256_cbc = "camellia-256-cbc";
enum NID_camellia_256_cbc = 753;
enum OBJ_camellia_256_cbc = "1L,2L,392L,200011L,61L,1L,1L,1L,4L";

enum OBJ_ntt_ds = "0L,3L,4401L,5L";

enum OBJ_camellia = "OBJ_ntt_ds,3L,1L,9L";

enum SN_camellia_128_ecb = "CAMELLIA-128-ECB";
enum LN_camellia_128_ecb = "camellia-128-ecb";
enum NID_camellia_128_ecb = 754;
enum OBJ_camellia_128_ecb = "OBJ_camellia,1L";

enum SN_camellia_128_ofb128 = "CAMELLIA-128-OFB";
enum LN_camellia_128_ofb128 = "camellia-128-ofb";
enum NID_camellia_128_ofb128 = 766;
enum OBJ_camellia_128_ofb128 = "OBJ_camellia,3L";

enum SN_camellia_128_cfb128 = "CAMELLIA-128-CFB";
enum LN_camellia_128_cfb128 = "camellia-128-cfb";
enum NID_camellia_128_cfb128 = 757;
enum OBJ_camellia_128_cfb128 = "OBJ_camellia,4L";

enum SN_camellia_192_ecb = "CAMELLIA-192-ECB";
enum LN_camellia_192_ecb = "camellia-192-ecb";
enum NID_camellia_192_ecb = 755;
enum OBJ_camellia_192_ecb = "OBJ_camellia,21L";

enum SN_camellia_192_ofb128 = "CAMELLIA-192-OFB";
enum LN_camellia_192_ofb128 = "camellia-192-ofb";
enum NID_camellia_192_ofb128 = 767;
enum OBJ_camellia_192_ofb128 = "OBJ_camellia,23L";

enum SN_camellia_192_cfb128 = "CAMELLIA-192-CFB";
enum LN_camellia_192_cfb128 = "camellia-192-cfb";
enum NID_camellia_192_cfb128 = 758;
enum OBJ_camellia_192_cfb128 = "OBJ_camellia,24L";

enum SN_camellia_256_ecb = "CAMELLIA-256-ECB";
enum LN_camellia_256_ecb = "camellia-256-ecb";
enum NID_camellia_256_ecb = 756;
enum OBJ_camellia_256_ecb = "OBJ_camellia,41L";

enum SN_camellia_256_ofb128 = "CAMELLIA-256-OFB";
enum LN_camellia_256_ofb128 = "camellia-256-ofb";
enum NID_camellia_256_ofb128 = 768;
enum OBJ_camellia_256_ofb128 = "OBJ_camellia,43L";

enum SN_camellia_256_cfb128 = "CAMELLIA-256-CFB";
enum LN_camellia_256_cfb128 = "camellia-256-cfb";
enum NID_camellia_256_cfb128 = 759;
enum OBJ_camellia_256_cfb128 = "OBJ_camellia,44L";

enum SN_camellia_128_cfb1 = "CAMELLIA-128-CFB1";
enum LN_camellia_128_cfb1 = "camellia-128-cfb1";
enum NID_camellia_128_cfb1 = 760;

enum SN_camellia_192_cfb1 = "CAMELLIA-192-CFB1";
enum LN_camellia_192_cfb1 = "camellia-192-cfb1";
enum NID_camellia_192_cfb1 = 761;

enum SN_camellia_256_cfb1 = "CAMELLIA-256-CFB1";
enum LN_camellia_256_cfb1 = "camellia-256-cfb1";
enum NID_camellia_256_cfb1 = 762;

enum SN_camellia_128_cfb8 = "CAMELLIA-128-CFB8";
enum LN_camellia_128_cfb8 = "camellia-128-cfb8";
enum NID_camellia_128_cfb8 = 763;

enum SN_camellia_192_cfb8 = "CAMELLIA-192-CFB8";
enum LN_camellia_192_cfb8 = "camellia-192-cfb8";
enum NID_camellia_192_cfb8 = 764;

enum SN_camellia_256_cfb8 = "CAMELLIA-256-CFB8";
enum LN_camellia_256_cfb8 = "camellia-256-cfb8";
enum NID_camellia_256_cfb8 = 765;

enum SN_kisa = "KISA";
enum LN_kisa = "kisa";
enum NID_kisa = 773;
enum OBJ_kisa = "OBJ_member_body,410L,200004L";

enum SN_seed_ecb = "SEED-ECB";
enum LN_seed_ecb = "seed-ecb";
enum NID_seed_ecb = 776;
enum OBJ_seed_ecb = "OBJ_kisa,1L,3L";

enum SN_seed_cbc = "SEED-CBC";
enum LN_seed_cbc = "seed-cbc";
enum NID_seed_cbc = 777;
enum OBJ_seed_cbc = "OBJ_kisa,1L,4L";

enum SN_seed_cfb128 = "SEED-CFB";
enum LN_seed_cfb128 = "seed-cfb";
enum NID_seed_cfb128 = 779;
enum OBJ_seed_cfb128 = "OBJ_kisa,1L,5L";

enum SN_seed_ofb128 = "SEED-OFB";
enum LN_seed_ofb128 = "seed-ofb";
enum NID_seed_ofb128 = 778;
enum OBJ_seed_ofb128 = "OBJ_kisa,1L,6L";

enum SN_hmac = "HMAC";
enum LN_hmac = "hmac";
enum NID_hmac = 855;
