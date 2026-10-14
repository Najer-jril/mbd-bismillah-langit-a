import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { listBookStatus, getBookStatusAudit, getBookStatus } from "../controllers/bookStatusController.js";

const router = Router();

router.get("/audit", withDb(getBookStatusAudit));
router.get("/:id", withDb(getBookStatus));
router.get("/", withDb(listBookStatus));

export default router;
