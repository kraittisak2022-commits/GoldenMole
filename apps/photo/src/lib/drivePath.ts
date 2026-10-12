import { folderPath, isValidReportDate, ROOT_FOLDER_NAME } from '../../shared/folderPath';

/** `GoldenMole Photos / 2569 / 10-ตุลาคม` for showing where an album is filed. */
export function drivePathLabel(reportDate: string): string {
  if (!isValidReportDate(reportDate)) return ROOT_FOLDER_NAME;
  const [year, month] = folderPath(reportDate);
  return `${ROOT_FOLDER_NAME} / ${year.name} / ${month.name}`;
}
