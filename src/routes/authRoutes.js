import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { login, logout, me } from "../controllers/authController.js";

const router = Router();

router.post("/login", withDb(login, { auth: false }));
router.post("/logout", withDb(logout));
router.get("/me", withDb(me));

export default router;
