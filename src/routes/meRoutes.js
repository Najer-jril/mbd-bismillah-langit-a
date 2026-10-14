import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { getMyQuota, listMyLoans, getMyLoan, listMyFines } from "../controllers/meController.js";

const router = Router();

router.get("/quota", withDb(getMyQuota));
router.get("/loans", withDb(listMyLoans));
router.get("/loans/:id", withDb(getMyLoan));
router.get("/fines", withDb(listMyFines));

export default router;
