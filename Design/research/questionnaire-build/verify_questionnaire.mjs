import fs from "node:fs/promises";
import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const workbookPath = path.resolve("Design/Babel-设计需求澄清问卷.xlsx");
const input = await FileBlob.load(workbookPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const summary = await workbook.inspect({
  kind: "table",
  range: "填写说明!A6:C10",
  include: "values,formulas",
  tableMaxRows: 5,
  tableMaxCols: 3,
  maxChars: 3000
});
console.log(summary.ndjson);

const ending = await workbook.inspect({
  kind: "table",
  range: "设计问卷!A47:H50",
  include: "values,formulas",
  tableMaxRows: 4,
  tableMaxCols: 8,
  maxChars: 5000
});
console.log(ending.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "reimported formula error scan"
});
console.log(errors.ndjson);

const preview = await workbook.render({
  sheetName: "设计问卷",
  range: "A1:H15",
  scale: 1,
  format: "png"
});
await fs.writeFile(
  path.resolve("Design/_build/previews/设计问卷-重新打开验证.png"),
  new Uint8Array(await preview.arrayBuffer())
);
