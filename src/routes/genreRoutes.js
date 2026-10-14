import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { listGenres } from "../controllers/genreController.js";

const router = Router();
router.get("/", withDb(listGenres));
export default router;
