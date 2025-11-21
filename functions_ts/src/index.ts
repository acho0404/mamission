import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

// ----------------------------------------------------------
// 🔥 AUTO CLOSE MISSION + NOTIFS Firestore
// ----------------------------------------------------------
export const autoCloseMission = onDocumentCreated(
  "reviews/{id}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const missionId = data.missionId;
    const reviewerId = data.reviewerId;

    if (!missionId) return;

    console.log("📝 Avis ajouté pour la mission :", missionId);

    // Lire tous les avis
    const reviewsSnap = await admin
      .firestore()
      .collection("reviews")
      .where("missionId", "==", missionId)
      .get();

    const totalReviews = reviewsSnap.size;

    // Anti doublon
    const already = reviewsSnap.docs.filter(
      (d) => d.data().reviewerId === reviewerId
    );

    if (already.length > 1) {
      console.log("⚠️ Avis dupliqué → ignoré");
      return;
    }

    // Pas encore 2 avis
    if (totalReviews < 2) {
      console.log("⏳ Pas encore 2 avis →", totalReviews);
      return;
    }

    // Mission close
    const missionRef = admin.firestore().collection("missions").doc(missionId);
    const missionDoc = await missionRef.get();
    const mission = missionDoc.data();

    if (!mission) return;

    const clientId = mission.posterId;
    const providerId = mission.assignedTo;

    await missionRef.update({
      status: "closed",
      closedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("✅ Mission automatiquement close :", missionId);

    // Créer 2 notifs Firestore
    const notifCol = admin.firestore().collection("notifications");

    const base = {
      type: "reviews_completed",
      title: "Avis complétés 🎉",
      body: "Vous et l'autre utilisateur avez laissé vos avis.",
      extra: {
        missionId,
        missionTitle: mission.title || "",
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    };

    await notifCol.add({ ...base, userId: clientId });
    await notifCol.add({ ...base, userId: providerId });

    console.log("📨 Notifs Firestore créées.");
  }
);

// ----------------------------------------------------------
// 🔥 ENVOI PUSH FCM AUTOMATIQUE depuis /notifications
// ----------------------------------------------------------
export const sendPushOnNotificationCreate = functions.firestore
  .document("notifications/{id}")
  .onCreate(async (snap, context) => {
    const notif = snap.data();
    if (!notif) return;

    const { userId, title, body, type, extra } = notif;

    // Get token FCM
    const userDoc = await admin.firestore()
      .collection("users")
      .doc(userId)
      .get();

    const token = userDoc.get("fcmToken");

    if (!token) {
      console.log("⚠️ Pas de token FCM pour", userId);
      return;
    }

    const message: admin.messaging.Message = {
      token,
      notification: {
        title: title || "Notification",
        body: body || "",
      },
      data: {
        type: type || "",
        missionId: extra?.missionId || "",
        missionTitle: extra?.missionTitle || "",
      },
    };

    try {
      await admin.messaging().send(message);
      console.log("📨 Push envoyé à:", userId);
    } catch (e) {
      console.error("❌ Erreur push:", e);
    }
  });
