const SAFE_NAME = /^[a-z_][a-z0-9_]*$/;

export async function callProc(conn, name, args = [], outs = []) {
    if (!SAFE_NAME.test(name)) {
        throw new Error(`Invalid procedure name: ${name}`);
    }

    const values = args.map((v) => (v !== null && typeof v === "object" ? JSON.stringify(v) : v));
    const placeholders = [...values.map(() => "?"), ...outs.map((o) => `@out_${o}`)].join(", ");

    const [result] = await conn.query(`CALL ${name}(${placeholders})`, values);
    const sets = Array.isArray(result) ? result.filter(Array.isArray) : [];

    let out = {};
    if (outs.length) {
        const select = outs.map((o) => `@out_${o}`).join(", ");
        const [[row]] = await conn.query(`SELECT ${select}`);
        out = Object.fromEntries(outs.map((o, i) => [o, row[`@out_${o}`]]));
    }
    return { rows: sets[0] ?? [], sets, out };
}

export async function select(conn, sql, params = []) {
    const [rows] = await conn.query(sql, params);
    return rows;
}

export function paginate(query) {
    const page = Math.max(parseInt(query.page, 10) || 1, 1);
    const limit = Math.min(Math.max(parseInt(query.limit, 10) || 20, 1), 100);
    return { page, limit, offset: (page - 1) * limit };
}

/**
 * SELECT * FROM <view> [WHERE ...] ORDER BY <orderBy> LIMIT/OFFSET, plus total.
 * `view` dan `orderBy` HARUS literal dari kode (bukan input user). `where` = array string berisi '?'.
 * Return { rows, meta: { page, limit, total } }
 */
export async function listView(conn, view, { where = [], params = [], orderBy, query }) {
    if (!/^[a-z_]+$/.test(view)) throw new Error("view tidak valid");
    const { page, limit, offset } = paginate(query);
    const w = where.length ? ` WHERE ${where.join(" AND ")}` : "";
    const [rows] = await conn.query(`SELECT * FROM ${view}${w} ORDER BY ${orderBy} LIMIT ? OFFSET ?`, [...params, limit, offset]);
    const [[{ total }]] = await conn.query(`SELECT COUNT(*) AS total FROM ${view}${w}`, params);
    return { rows, meta: { page, limit, total } };
}
