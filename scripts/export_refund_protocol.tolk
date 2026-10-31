import "@acton/boc"
import "@acton/fs"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@contracts/common/nft/deliveries"
import "@contracts/common/nft/enums"
import "@contracts/common/offer/messages"
import "../tests/refund_batching/fixture"

// Только локальная генерация канонических wire fixtures. Никогда не подписывает/не отправляет в сеть.
fun main() {
    assert (!net.isBroadcasting()) throw 9800;
    testing.setNow(1793196411);
    val recipient = address("0:232554efdf4e13d527545f0c25ad3f543a829fe7ea86924a7befdaede67a2caf");
    val record = NftDelivery {
        recipient,
        queryId: 42,
        automaticReserve: 123456789,
        status: NftDeliveryStatus.Failed,
    }.toCell();
    assert (
        fs.writeBytes(
            "tests/refund_batching/fixtures/delivery-v2.boc",
            boc.encode(record, { crc32: true }),
        )
    ) throw 9801;
    assert (
        fs.writeBytes(
            "tests/refund_batching/fixtures/claim-v2.boc",
            boc.encode(ClaimEscrowSurplus { queryId: 42 }.toCell(), { crc32: true }),
        )
    ) throw 9802;
    val exact = fixture(false, 3);
    assert (txExit(exact.resume()) == 0) throw 9803;
    assert (
        fs.writeBytes(
            "tests/refund_batching/fixtures/exact-settled-v2.boc",
            boc.encode(exact.state(), { crc32: true }),
        )
    ) throw 9804;
    val certified = fixture(true, 3);
    assert (txExit(certified.resume()) == 0) throw 9805;
    assert (
        fs.writeBytes(
            "tests/refund_batching/fixtures/certified-settled-v2.boc",
            boc.encode(certified.state(), { crc32: true }),
        )
    ) throw 9806;
    println("Canonical v2 claim/delivery/settled state fixtures generated locally");
}
