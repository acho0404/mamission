"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.autoCloseMission = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();
// 🔥 V2 — Fermeture automatique d'une mission si 2 avis
exports.autoCloseMission = (0, firestore_1.onDocumentCreated)("reviews/{id}", async (event) => {
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    const missionId = data.missionId;
    if (!missionId)
        return;
    // 1. Récupérer tous les avis associés à cette mission
    const reviewsSnap = await admin.firestore()
        .collection("reviews")
        .where("missionId", "==", missionId)
        .get();
    // 2. Si 2 avis → clôture automatique
    if (reviewsSnap.size >= 2) {
        await admin.firestore()
            .collection("missions")
            .doc(missionId)
            .update({
            status: "closed",
            closedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
});
