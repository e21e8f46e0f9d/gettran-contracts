import "@acton/emulation/config"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@contracts/common/nft/recovery_messages"
import "@contracts/common/nft/transfers"
import "fixture"

fun changeGasPrice(numerator: int, denominator: int) {
    var config = testing.getConfig();
    var gas = config.getGasPrices(BASECHAIN);
    gas.other.gasPrice = gas.other.gasPrice * numerator / denominator;
    gas.flatGasPrice = gas.flatGasPrice * numerator / denominator;
    config.setGasPrices(gas, BASECHAIN);
    assert (testing.setConfig(config)) throw 2601;
}

fun assertRaisedPrices(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2602;
    val allocation = f.budget();
    changeGasPrice(2, 1);
    assert (txExit(f.bounce(0)) == 0) throw 2603;
    val rejected = net.sendExternal(
        net.createExternalMessage(
            f.escrow,
            TriggerNftDeliveryRetry {
                offerId: 15,
                nft: f.nfts.get(0),
                deliveryQueryId: f.deliveryQuery(0),
            },
        ),
    );
    assert (rejected.transactions == null) throw 2604;
    assert (f.budget() == allocation) throw 2605;
    // Цена изменилась, но подтверждение освобождает записанную аллокацию, не текущую стоимость.
    val manual = f.receive(f.beneficiary, ConfirmNftDelivery { nft: f.nfts.get(0) }.toCell());
    assert (txExit(manual) == 0) throw 2606;
    assert (f.budget() == allocation / 2) throw 2607;
    assert (txExit(f.ack(1)) == 0) throw 2608;
    assert (f.budget() == 0) throw 2609;
}

get fun `test certified higher fees cannot borrow another delivery reserve`() {
    assertRaisedPrices(true);
}

get fun `test exact higher fees cannot borrow another delivery reserve`() {
    assertRaisedPrices(false);
}

fun assertLowerPrices(certified: bool) {
    val f = fixture(certified, 2);
    assert (txExit(f.resume()) == 0) throw 2701;
    val total = f.budget();
    val original = f.deliveries().get(f.nfts.get(0)).loadValue().automaticReserve;
    changeGasPrice(1, 2);
    assert (txExit(f.bounce(0)) == 0) throw 2702;
    val cost = requiredNftRetryValue();
    val cursor = testing.createExternalTraceIterationCursor(
        net.createExternalMessage(
            f.escrow,
            TriggerNftDeliveryRetry {
                offerId: 15,
                nft: f.nfts.get(0),
                deliveryQueryId: f.deliveryQuery(0),
            },
        ),
    );
    val res = cursor.executeN(1);
    cursor.close();
    assert (txExit(res.at(0)) == 0) throw 2703;
    assert (f.budget() == total - cost) throw 2704;
    assert (
        f.deliveries().get(f.nfts.get(0)).loadValue().automaticReserve == original - cost
    ) throw 2705;
    assert (txExit(f.ack(0)) == 0) throw 2706;
    assert (f.budget() == total - original) throw 2707;
    assert (txExit(f.ack(1)) == 0 && f.budget() == 0) throw 2708;
}

get fun `test certified cheaper retry releases exact unspent allocation`() {
    assertLowerPrices(true);
}

get fun `test exact cheaper retry releases exact unspent allocation`() {
    assertLowerPrices(false);
}
