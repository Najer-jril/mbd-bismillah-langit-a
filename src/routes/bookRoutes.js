import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { listBooks, getBook, getBookEligibility, createBook, updateBook, deleteBook } from "../controllers/bookController.js";

const router = Router();

router.get("/", withDb(listBooks));
router.post("/", withDb(createBook));
router.get("/:id/eligibility", withDb(getBookEligibility));
router.get("/:id", withDb(getBook));
router.patch("/:id", withDb(updateBook));
router.delete("/:id", withDb(deleteBook));

export default router;
