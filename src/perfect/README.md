# How to Use

## Database Setup

1. Navigate to the [Perfect Database](http://compalg.inf.elte.hu/~ggevay/mills/index.php) and download the zip file.
2. Once downloaded, extract the contents of the zip file to your desired directory.

## Building and Running the Project

1. Execute the batch file located at `src\ui\qt\build.bat` to prepare the build environment.
2. Open Microsoft Visual Studio and load the solution file `mill-pro.sln`.
3. Open the `option.h` file and specify the path to the Perfect Database by setting the `perfectDatabasePath` variable.
4. Edit the `settings.int` file and update the `PerfectDatabasePath` field with the full directory path where you've downloaded the database. For example, you may set it to `E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted`. Note that backslashes `\` in the path should be escaped as double backslashes `\\`.
5. Build and run the project within Visual Studio.

## Game Setup

1. Once the application is operational, navigate to the menu and select `Rules -> Nine men's morris`. If this doesn't take effect, manually modify the `settings.ini` file and set the `RuleNo` value to `0`.
2. Navigate to `AI` and select `Use Perfect Database`.

You are now ready to engage in a game against the Perfect AI.

## Acknowledgments

Sincere appreciation is extended to [Gabor E. Gevay](https://github.com/ggevay) and [Gabor Danner](https://github.com/DannerG) for their invaluable contributions. Beyond developing the Perfect Database, they have also authored a compelling paper on the subject: [Calculating Ultra-Strong and Extended Solutions for Nine Men's Morris, Morabaraba, and Lasker Morris](https://ieeexplore.ieee.org/abstract/document/7080922). In addition, they have contributed to the development of the related source code. Their collective work serves as both the foundation and the intellectual backbone for this component.