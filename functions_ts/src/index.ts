import * as functions from "firebase-functions/v2";
import { onRequest, onCall } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import Stripe from "stripe";

admin.initializeApp();

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY as string, {
  apiVersion: "2024-06-20" as any,
});

// createPaymentIntent callable
export const createPaymentIntent = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 60 },
  async (request) => {
    const amount = Number(request.data.amount);
    const currency = (request.data.currency || "eur").toString();
    const description = (request.data.description || "Mission payment").toString();

    if (!amount || amount <= 0) {
      throw new functions.https.HttpsError("invalid-argument", "Montant invalide");
    }

    const intent = await stripe.paymentIntents.create({
      amount,
      currency,
      description,
      automatic_payment_methods: { enabled: true },
    });

    return { clientSecret: intent.client_secret };
  }
);

// stripeWebhook
export const stripeWebhook = onRequest(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 60 },
  async (req, res) => {
    const sig = req.headers["stripe-signature"] as string;
    const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET as string;
    let event: Stripe.Event;

    try {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
    } catch (err: any) {
      console.error("⚠️ Signature Stripe invalide :", err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    switch (event.type) {
      case "payment_intent.succeeded":
        console.log("✅ Paiement réussi :", event.data.object["id"]);
        break;
      case "payment_intent.payment_failed":
        console.log("❌ Paiement échoué :", event.data.object["id"]);
        break;
      default:
        console.log("ℹ️ Événement Stripe :", event.type);
    }

    res.json({ received: true });
  }
);
