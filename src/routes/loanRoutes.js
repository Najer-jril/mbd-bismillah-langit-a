import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { createLoan, listLoans, getLoan, approveLoan, rejectLoan, returnLoan } from "../controllers/loanController.js";

const router = Router();

router.post("/", withDb(createLoan));
router.get("/", withDb(listLoans));
router.get("/:id", withDb(getLoan));
router.post("/:id/approve", withDb(approveLoan));
router.post("/:id/reject", withDb(rejectLoan));
router.post("/:id/return", withDb(returnLoan));

export default router;
