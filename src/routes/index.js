import { Router } from "express";
import authRoutes from "./authRoutes.js";
import userRoutes from "./userRoutes.js";
import bookRoutes from "./bookRoutes.js";
import genreRoutes from "./genreRoutes.js";
import authorRoutes from "./authorRoutes.js";
import bookStatusRoutes from "./bookStatusRoutes.js";
import loanRoutes from "./loanRoutes.js";
import fineRoutes from "./fineRoutes.js";
import meRoutes from "./meRoutes.js";

const router = Router();

router.get("/health", (req, res) => {
  res.json({ message: "OK" });
});

router.use("/auth", authRoutes);
router.use("/users", userRoutes);
router.use("/books", bookRoutes);
router.use("/genres", genreRoutes);
router.use("/authors", authorRoutes);
router.use("/book-status", bookStatusRoutes);
router.use("/loans", loanRoutes);
router.use("/fines", fineRoutes);
router.use("/me", meRoutes);

export default router;
