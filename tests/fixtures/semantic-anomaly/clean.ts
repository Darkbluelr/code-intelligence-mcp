import { logger } from "./logger";

async function fetchUser(id: string): Promise<string> {
  try {
    logger.info("Fetching user", { id });
    const response = await fetch("/api/users/" + id);
    if (!response.ok) {
      throw new Error("Fetch failed");
    }
    const user = await response.text();
    logger.info("User fetched", { id });
    return user;
  } catch (error) {
    logger.error("Fetch failed", { id, error });
    throw error;
  }
}

function paymentHandled(amount: number): number {
  logger.info("payment", { amount });
  return amount * 2;
}

function useLogger() {
  logger.info("ok");
}
