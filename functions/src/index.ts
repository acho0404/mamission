import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import Stripe from "stripe";

// 🔐 MET ICI TA CLÉ SECRÈTE STRIPE TEST (sk_test_...)
const stripe = new Stripe("sk_test_51SOjsWFqamUyjlkCKlOAcXPCDhoUKmOZKrEYX14JSaZ9tHZ8ZUFsTQyNq25tWdnLNwCmEPiCJPnAxIwkn3Rdm8MR00T7BPjlzM", {
  apiVersion: "2024-06-20",
});

admin.initializeApp();

const db = admin.firestore();

/* ---------------------------------------------------------------------------
 💳 CRÉATION DE L'INTENTION DE PAIEMENT (Stripe)
--------------------------------------------------------------------------- */
export const createPaymentIntent = functions.https.onCall(
  async (data: any, context: any) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Vous devez être connecté."
      );
    }

    const amount = data.amount; // en centimes
    const currency = data.currency || "eur";

    if (!amount || amount < 50) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Montant invalide (min 0.50€)."
      );
    }

    try {
      const paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency,
        automatic_payment_methods: { enabled: true },
        metadata: {
          userId: context.auth.uid,
        },
      });

      return {
        clientSecret: paymentIntent.client_secret,
      };
    } catch (error: any) {
      console.error("Erreur Stripe:", error);
      throw new functions.https.HttpsError("internal", error.message);
    }
  }
);

/* ---------------------------------------------------------------------------
 🔥 AUTO-CLOSE MISSION LORSQUE LES 2 AVIS SONT POSTÉS
--------------------------------------------------------------------------- */
export const autoCloseMission = onDocumentCreated(
  "reviews/{id}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const missionId = data?.missionId;
    const reviewerId = data?.reviewerId;
    if (!missionId) return;

    console.log("⭐ Nouvel avis pour la mission:", missionId);

    const reviewsSnap = await db
      .collection("reviews")
      .where("missionId", "==", missionId)
      .get();

    const totalReviews = reviewsSnap.size;

    const duplicates = reviewsSnap.docs.filter(
      (d) => d.data().reviewerId === reviewerId
    );
    if (duplicates.length > 1) {
      console.log("⛔ Avis en double → ignoré");
      return;
    }

    if (totalReviews < 2) {
      console.log("⏳ Pas encore 2 avis (actuels:", totalReviews, ")");
      return;
    }

    const missionRef = db.collection("missions").doc(missionId);
    const missionSnap = await missionRef.get();
    if (!missionSnap.exists) return;

    const mission = missionSnap.data() || {};
    const clientId = mission.posterId;
    const providerId = mission.assignedTo;

    await missionRef.update({
      status: "closed",
      closedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("✅ Mission automatiquement fermée:", missionId);

    const notifCol = db.collection("notifications");
    const base = {
      type: "reviews_completed",
      title: "Avis complétés 🎉",
      body: "Votre mission est maintenant terminée.",
      extra: {
        missionId,
        missionTitle: mission.title || "",
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    };

    if (clientId) {
      const doc = notifCol.doc();
      await doc.set({ ...base, userId: clientId, id: doc.id });
    }

    if (providerId) {
      const doc = notifCol.doc();
      await doc.set({ ...base, userId: providerId, id: doc.id });
    }

    console.log("📨 Notifs Firestore créées.");
  }
);

/* ---------------------------------------------------------------------------
 🔥 NOTIF AUTOMATIQUE SUR NOUVEAU MESSAGE DE CHAT
--------------------------------------------------------------------------- */
export const onNewChatMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as any;
    const chatId = event.params.chatId as string;
    const fromUserId = data?.from as string | undefined;
    const text = (data?.text as string | undefined) || "";

    if (!fromUserId || !text) {
      console.log("⚠️ Message de chat incomplet, on skip.");
      return;
    }

    console.log("💬 Nouveau message dans le chat:", chatId);

    const chatSnap = await db.collection("chats").doc(chatId).get();
    if (!chatSnap.exists) {
      console.log("⚠️ Chat inexistant:", chatId);
      return;
    }

    const chat = chatSnap.data() || {};

    const rawUsers =
      (chat as any).users ||
      (chat as any).usersIds ||
      (chat as any).participants ||
      [];

    const participants = Array.from(rawUsers || []) as string[];

    const notifCol = db.collection("notifications");

    const userNames = (chat as any).userNames || {};
    const senderName = userNames[fromUserId] || "Nouveau message";

    const snippet = text.length > 80 ? text.substring(0, 77) + "..." : text;

    const promises = participants
      .filter((uid: string) => uid !== fromUserId)
      .map(async (toUserId: string) => {
        const userSnap = await db.collection("users").doc(toUserId).get();
        if (!userSnap.exists) return;

        const user = userSnap.data() || {};
        const activeChatId = user.activeChatId as string | undefined;

        if (activeChatId === chatId) {
          console.log(
            `👀 User ${toUserId} est déjà dans le chat ${chatId}, pas de notif.`
          );
          return;
        }

        const doc = notifCol.doc();
        await doc.set({
          id: doc.id,
          userId: toUserId,
          type: "chat_message",
          title: senderName,
          body: snippet,
          extra: { chatId, fromUserId },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
        });

        console.log("📝 Notif Firestore chat_message créée pour", toUserId);
      });

    await Promise.all(promises);

    console.log("✅ onNewChatMessage terminé pour chat", chatId);
  }
);

/* ---------------------------------------------------------------------------
 🔥 PUSH FCM SUR NOUVELLE NOTIF FIRESTORE
--------------------------------------------------------------------------- */
export const sendPushOnNotificationCreate = onDocumentCreated(
  "notifications/{id}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const notif = snap.data();
    if (!notif) return;

    const userId = notif.userId;
    if (!userId) {
      console.log("⚠️ Notification sans userId, ignorée.");
      return;
    }

    const title = notif.title;
    const body = notif.body;
    const type = notif.type;
    const extra = notif.extra || {};

    console.log("📬 Nouvelle notif Firestore → PUSH pour", userId);

    const userDoc = await db.collection("users").doc(userId).get();
    const token = userDoc.get("fcmToken");

    if (!token) {
      console.log("⚠️ Pas de token FCM pour", userId);
      return;
    }

    const message = {
      token,
      notification: {
        title: title || "Notification",
        body: body || "",
      },
      data: {
        type: type || "",
        missionId: extra.missionId || "",
        missionTitle: extra.missionTitle || "",
        chatId: extra.chatId || "",
        fromUserId: extra.fromUserId || "",
      },
    };

    try {
      await admin.messaging().send(message);
      console.log("📨 PUSH envoyé à", userId);
    } catch (err) {
      console.error("❌ Erreur envoi push:", err);
    }
  }
);
