import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { listFines, getFine, payFine } from "../controllers/fineController.js";

const router = Router();

router.get("/", withDb(listFines));
router.get("/:id", withDb(getFine));
router.post("/:id/pay", withDb(payFine));

export default router;
