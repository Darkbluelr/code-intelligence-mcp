import { unusedA } from "./unused";
import { logger } from "./logger";

async function fetchData() {
  await fetch("/api/data");
}

const snake_case_var = 1;

function paymentProcess(amount: number) {
  return amount * 2;
}

function logStuff() {
  console.log("x");
  logger.info("y");
}

function useLogger() {
  logger.info("ok");
}
