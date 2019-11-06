package testcases;

class TestTextEditHelper {
	public static function compareTextEdits(goldEdits:Array<TextEdit>, actualEdits:Array<TextEdit>) {
		Assert.notNull(actualEdits);
		Assert.notNull(goldEdits);
		Assert.equals(goldEdits.length, actualEdits.length);
		for (index in 0...goldEdits.length) {
			var expectedEdit:TextEdit = goldEdits[index];
			var actualEdit:TextEdit = actualEdits[index];
			Assert.equals(expectedEdit.newText, actualEdit.newText);
			if (expectedEdit.range != null) {
				Assert.equals(expectedEdit.range.start.line, actualEdit.range.start.line);
				Assert.equals(expectedEdit.range.start.character, actualEdit.range.start.character);
				Assert.equals(expectedEdit.range.end.line, actualEdit.range.end.line);
				Assert.equals(expectedEdit.range.end.character, actualEdit.range.end.character);
			}
		}
	}
}
