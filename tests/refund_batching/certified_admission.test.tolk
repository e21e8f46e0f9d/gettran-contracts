import "@acton/crypto"
import "@acton/emulation/testing"
import "@contracts/certified_offer_escrow/constants"
import "@contracts/certified_offer_escrow/messages"
import "@contracts/certified_offer_escrow/storage"
import "@contracts/common/offer/wallets"
import "fixture"

// All-onchain sale legitimately needs the platform certificate for Telegram admission.
// An absent provider/criterion does not replace immutable certificate/signature/party guards.
fun assertCertifiedAdmissionRejects(wrongSignature: bool) {
    testing.setChecksigIgnore(false);
    val f = fixture(
        true,
        3,
        false,
        true,
        false,
        0,
        true,
    );
    val certifier = crypto.generateKeyPair();
    val stranger = crypto.generateKeyPair();
    var storage = CertifiedOfferEscrowStorage.fromCell(f.state());
    storage.certifierPublicKey = certifier.publicKey;
    storage.executionAttempt = null;
    f.seedRecordedState(storage.toCell());
    val certificate = CertifiedExecutionCertificate {
        domain: CERTIFIED_EXECUTION_DOMAIN,
        schemaVersion: CERTIFIED_EXECUTION_SCHEMA_VERSION,
        escrow: f.escrow,
        offerId: 15,
        offerExecutionNumber: 0,
        validUntil: testing.getNow() + 60,
        requirementCommitment: 0,
        details: CertifiedExecutionCertificateDetails {
            contributorWallets: singleOfferWallet(f.beneficiary),
            takerSettlementWallet: f.beneficiary,
            delivery: null,
            takerTonFee: 0,
        }.toCell(),
    }.toCell();
    val before = f.state().hash();
    val rejected = f.receive(
        wrongSignature ? f.beneficiary : f.stranger,
        BuyCertifiedOffer {
            queryId: 1,
            paymentAmount: grams("1"),
            signature: crypto.sign(
                wrongSignature ? stranger.privateKey : certifier.privateKey,
                certificate,
            ) as bits512,
            signed: certificate,
        }.toCell(),
        grams("1.2"),
    );
    assert (txExit(rejected) != 0) throw 5301;
    assert (f.state().hash() == before) throw 5302;
    val admitted = f.receive(
        f.beneficiary,
        BuyCertifiedOffer {
            queryId: 2,
            paymentAmount: grams("1"),
            signature: crypto.sign(certifier.privateKey, certificate) as bits512,
            signed: certificate,
        }.toCell(),
        grams("1.2"),
    );
    assert (txExit(admitted) == 0) throw 5303;
}

get fun `test all-onchain certified admission still rejects invalid certifier signature`() {
    assertCertifiedAdmissionRejects(true);
}

get fun `test all-onchain certified admission still rejects unauthorized payer`() {
    assertCertifiedAdmissionRejects(false);
}
