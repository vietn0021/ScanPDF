import {parentPort, workerData} from 'node:worker_threads';
import {PDFDocument} from 'pdf-lib';

try {
  const doc = await PDFDocument.load(workerData, {throwOnInvalidObject: true, updateMetadata: false});
  parentPort.postMessage(doc.getPageCount());
} catch {
  parentPort.postMessage(null);
}
