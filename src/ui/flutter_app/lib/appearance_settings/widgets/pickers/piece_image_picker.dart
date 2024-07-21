part of 'package:sanmill/appearance_settings/widgets/appearance_settings_page.dart';

final List<String> _pieceBgPaths = <String>[
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
        label: S.of(context).pieces, // TODO: pieceImage
        child: ValueListenableBuilder<Box<DisplaySettings>>(
          valueListenable: DB().listenDisplaySettings,
          builder: (BuildContext context, Box<DisplaySettings> box, _) {
            final DisplaySettings displaySettings = box.get(
              DB.displaySettingsKey,
              defaultValue: const DisplaySettings(),
            )!;

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 20), // Add vertical padding
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
  ) {
    return Row(
      children: <Widget>[
        Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 12), // Add left padding
          child: Text(
            playerLabel,
            style: TextStyle(color: DB().colorSettings.boardLineColor),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 60, // Ensure a fixed height for the ListView
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pieceBgPaths.length,
              itemBuilder: (BuildContext context, int index) {
                final String asset = _pieceBgPaths[index];
                final bool isSelectable = asset != otherPlayerSelectedImagePath;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: isSelectable
                        ? () {
                            onImageSelected(asset);
                          }
                        : null,
                    child: Opacity(
                      opacity: isSelectable ? 1.0 : 0.9,
                      child: _PieceImageItem(
                        asset: asset,
                        isSelect: selectedImagePath == asset,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16), // Add right padding
          child: Container(), // Empty container to add padding to the right
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
          const Positioned(
            right: 8,
            top: 8,
            child: Icon(
              Icons.check_circle,
              color: Colors.green,
            ),
          ),
      ],
    );
  }
}
