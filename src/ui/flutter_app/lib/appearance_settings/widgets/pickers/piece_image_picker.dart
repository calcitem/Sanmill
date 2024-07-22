part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

final List<String> _pieceBgPaths = <String>[
  '', // Pure color
  Assets.images.whitePieceImage1.path,
  Assets.images.blackPieceImage1.path,
  Assets.images.whitePieceImage2.path,
  Assets.images.blackPieceImage2.path,
  Assets.images.whitePieceImage3.path,
  Assets.images.blackPieceImage3.path,
];

class _PieceImagePicker extends StatelessWidget {
  const _PieceImagePicker();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DB().colorSettings.boardBackgroundColor,
      child: Semantics(
        label: S.of(context).pieces,
        child: ValueListenableBuilder<Box<DisplaySettings>>(
          valueListenable: DB().listenDisplaySettings,
          builder: (BuildContext context, Box<DisplaySettings> box, _) {
            final DisplaySettings displaySettings = box.get(
              DB.displaySettingsKey,
              defaultValue: const DisplaySettings(),
            )!;

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Row for Player 1
                    _buildPlayerRow(
                      context,
                      S.of(context).player1,
                      displaySettings.whitePieceImagePath,
                      (String asset) {
                        DB().displaySettings = displaySettings.copyWith(
                            whitePieceImagePath: asset);
                      },
                      displaySettings.blackPieceImagePath,
                      isPlayerOne: true,
                    ),
                    const SizedBox(height: 20),
                    // Row for Player 2
                    _buildPlayerRow(
                      context,
                      S.of(context).player2,
                      displaySettings.blackPieceImagePath,
                      (String asset) {
                        DB().displaySettings = displaySettings.copyWith(
                            blackPieceImagePath: asset);
                      },
                      displaySettings.whitePieceImagePath,
                      isPlayerOne: false,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayerRow(
      BuildContext context,
      String playerLabel,
      String selectedImagePath,
      void Function(String) onImageSelected,
      String otherPlayerSelectedImagePath,
      {required bool isPlayerOne}) {
    return Row(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Text(
            playerLabel,
            style: TextStyle(color: DB().colorSettings.boardLineColor),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pieceBgPaths.length,
              itemBuilder: (BuildContext context, int index) {
                final String asset = _pieceBgPaths[index];
                final bool isSelectable =
                    index == 0 || asset != otherPlayerSelectedImagePath;
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: isSelectable ? () => onImageSelected(asset) : null,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isPlayerOne
                              ? DB().colorSettings.whitePieceColor
                              : DB().colorSettings.blackPieceColor,
                          shape: BoxShape.circle,
                          border: selectedImagePath == asset
                              ? Border.all(color: Colors.blue, width: 2)
                              : null,
                        ),
                        child: selectedImagePath == asset
                            ? const Align(
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                              )
                            : null,
                      ),
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: isSelectable ? () => onImageSelected(asset) : null,
                      child: _PieceImageItem(
                        asset: asset,
                        isSelect: selectedImagePath == asset,
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(),
        ),
      ],
    );
  }
}

class _PieceImageItem extends StatelessWidget {
  const _PieceImageItem({
    required this.asset,
    this.isSelect = false,
  });

  final String asset;
  final bool isSelect;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(asset),
              fit: BoxFit.contain,
            ),
            border: isSelect ? Border.all(color: Colors.blue, width: 2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        if (isSelect)
          const Align(
            child: Icon(
              Icons.check_circle,
              color: Colors.green,
            ),
          ),
      ],
    );
  }
}
