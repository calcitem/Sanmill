# User Guide for Setting Up and Running Perfect AI

## Database Setup

Navigate to the [Perfect Database](http://compalg.inf.elte.hu/~ggevay/mills/index.php) and download the zip file.
> **Note**: The Perfect Database currently only supports the standard Nine/Twelve/Lasker Men's Morris rules and does not support other rule variants.

Once downloaded, extract the contents of the zip file to your desired directory.
> You may delete some database files to save space. If the AI cannot find these parts of the database, it will resort to traditional AI algorithms for the best moves.

## Building and Running the Project (For Users With Source Code)

* Execute the script file located at `src\ui\qt\build.bat` for Windows or `src/ui/qt/build.sh` for Linux to prepare the build environment. This will also generate the executable files.

* If you have Microsoft Visual Studio, you can load the solution file `mill-pro.sln`. Alternatively, you can use Qt Creator to open the `CMakeLists.txt` file for building the project.

* Optionally, open the `option.h` file and specify the path to the Perfect Database by setting the `perfectDatabasePath` variable. Note that this is not mandatory, as the path specified in the `settings.ini` file will override the hardcoded path in the code.

* Build and run the project within your chosen development environment.

Certainly, the revised section would look like this:

## Configuration Setup

Edit the `settings.ini` file to update the `PerfectDatabasePath` field with the full directory path where you've downloaded the database.
> Note: On Linux, replace double backslashes `\\` with a single forward slash `/`.
>
> Important: The `settings.ini` file will be generated upon the first run of the application. You can find this file in the same directory as the executable program. If you are running the application from an IDE, the location where `settings.ini` is generated may vary.

## Game Setup

* Once the application is operational, navigate to the menu and select `Rules -> Nine men's morris`.

* Navigate to `AI` and select `Use Perfect Database`.

**Note**:

Once you activate `Use Perfect Database`, the `Move Randomly` option cannot be disabled and will remain active. This issue will be fixed in future versions.

**Troubleshooting**:

If the AI doesn't result in all drawn games during self-play, it indicates that the database loading has failed or is incomplete. It's recommended to run the program from the command line to observe console output.

You are now ready to engage in a game against the Perfect AI.

## Acknowledgments

Sincere appreciation is extended to [Gabor E. Gevay](https://github.com/ggevay) and [Gabor Danner](https://github.com/DannerG) for their invaluable contributions. Beyond developing the Perfect Database, they have also authored a compelling paper on the subject: [Calculating Ultra-Strong and Extended Solutions for Nine Men's Morris, Morabaraba, and Lasker Morris](https://ieeexplore.ieee.org/abstract/document/7080922). In addition, they have contributed to the development of the related source code. Their collective work serves as both the foundation and the intellectual backbone for this component.
