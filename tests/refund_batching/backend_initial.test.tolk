import "@acton/boc"
import "@acton/build"
import "@acton/fs"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@contracts/common/nft/messages"
import "fixture"

// Эти initial data cells созданы реальным backend TonOfferEscrowFactory(profile=2).
// Проверяем не повторную Python-сериализацию, а адрес, TVM receive и реальные getters обоих runtime.
fun assertBackendInitial(certified: bool) {
    val data = boc.decode(
        fs.readBytes(
            certified
                ? "tests/refund_batching/fixtures/backend_initial/certified-data.boc"
                : "tests/refund_batching/fixtures/backend_initial/exact-data.boc",
        )!,
    )!;
    val code = certified ? build("CertifiedOfferEscrow") : build("OfferEscrow");
    val init: AutoDeployAddress = { workchain: 0, stateInit: { code, data } };
    val expected = address.fromWorkchainAndHash(
        0,
        certified
            ? 0x9fa8dba91bbe6cc5047f92b36069b5aa1dd24a9376a549ca82bdc41d25ddfbae
            : 0xb63c855ba525c3691b3321ad76379a6786b9e3a35b2808a07fee4b9cda1f0a8d,
    );
    assert (init.calculateAddress() == expected) throw 3901;
    val result = testing.processSingleTraceStep(
        testing.treasury("backend-interop").address,
        createMessage({
            bounce: false,
            dest: init,
            value: grams("0.2"),
            body: NftReportStaticData {
                queryId: 0,
                index: 0,
                collection: null,
            },
        }),
    );
    assert (txExit(result) == 0) throw 3902;
    assert (net.runGetMethod<int>(expected, "offer_id") == 12345) throw 3903;
    assert (net.runGetMethod<int>(expected, "offer_execution_number") == 0) throw 3904;
    assert (net.runGetMethod<coins>(expected, "required_maker_balance") > 0) throw 3905;
}

get fun `test backend exact profile2 initial data executes at its predicted address`() {
    assertBackendInitial(false);
}

get fun `test backend certified profile2 initial data executes at its predicted address`() {
    assertBackendInitial(true);
}
