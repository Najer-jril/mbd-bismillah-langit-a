import { Router } from "express";
import { withDb } from "../middlewares/withDb.js";
import { createUser, updateUserStatus, listUsers, getUser } from "../controllers/userController.js";

const router = Router();

router.post("/", withDb(createUser));
router.patch("/:id/status", withDb(updateUserStatus));
router.get("/", withDb(listUsers));
router.get("/:id", withDb(getUser));

export default router;
