import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { listAuthors, createAuthor } from "../controllers/authorController.js";

const router = Router();
router.get("/", withDb(listAuthors));
router.post("/", withDb(createAuthor));
export default router;
