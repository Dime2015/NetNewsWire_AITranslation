import path from "node:path";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const workbookPath = path.resolve("../Babel-设计需求澄清问卷.xlsx");
const input = await FileBlob.load(workbookPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const sheets = await workbook.inspect({
  kind: "sheet",
  include: "id,name",
  maxChars: 3000,
});
console.log(sheets.ndjson);

const answers = await workbook.inspect({
  kind: "table",
  range: "设计问卷!A1:H50",
  include: "values,formulas",
  tableMaxRows: 50,
  tableMaxCols: 8,
  tableMaxCellChars: 2000,
  maxChars: 120000,
});
console.log(answers.ndjson);

const summary = await workbook.inspect({
  kind: "table",
  range: "填写说明!A1:C10",
  include: "values,formulas",
  tableMaxRows: 10,
  tableMaxCols: 3,
  tableMaxCellChars: 1000,
  maxChars: 12000,
});
console.log(summary.ndjson);
