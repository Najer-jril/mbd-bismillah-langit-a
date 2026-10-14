import express from "express";
import cors from "cors";
import helmet from "helmet";
import routes from "./routes/index.js";
import { errorHandler, notFoundRoute } from "./middlewares/errorHandler.js";

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || "*" }));
app.use(express.json({ limit: "100kb" }));

app.use("/api", routes);

app.use(notFoundRoute);
app.use(errorHandler);

export default app;