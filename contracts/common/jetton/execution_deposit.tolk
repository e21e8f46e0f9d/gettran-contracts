// Связывает асинхронное Jetton-уведомление с конкретной попыткой принятия offer. Для NFT такой
// маркер не нужен: там источник и слот однозначно задаются NFT address и previousOwner.
struct (0x4a41464e) JettonExecutionDeposit {
    // "JAFN"
    offerExecutionNumber: uint32
}

fun readJettonExecutionNumber(payload: slice): uint32? {
    var envelope = payload;
    if (envelope.remainingBitsCount() < 1) {
        return null;
    }

    val isStoredInRef = envelope.loadUint(1) == 1;
    var body = envelope;
    if (isStoredInRef) {
        if (envelope.remainingBitsCount() != 0 || envelope.remainingRefsCount() != 1) {
            return null;
        }
        body = envelope.loadRef().beginParse();
    }
    if (body.remainingBitsCount() != 64 || body.remainingRefsCount() != 0) {
        return null;
    }
    if (body.loadUint(32) != 0x4a41464e) {
        return null;
    }
    return body.loadUint(32) as uint32;
}

fun isEmptyJettonForwardPayload(payload: slice): bool {
    var envelope = payload;
    if (envelope.remainingBitsCount() < 1) {
        return false;
    }

    if (envelope.loadUint(1) == 0) {
        return envelope.isEmpty();
    }
    if (envelope.remainingBitsCount() != 0 || envelope.remainingRefsCount() != 1) {
        return false;
    }
    return envelope.loadRef().beginParse().isEmpty();
}
