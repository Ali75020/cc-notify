using System;using System.IO;using System.Diagnostics;using System.Windows.Forms;using System.Drawing;
class S:Form{const string IB="iVBORw0KGgoAAAANSUhEUgAAAgAAAAIACAYAAAD0eNT6AAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAP+VJREFU...";const string NB="cGFyYW0oDQogICAgW3N0cmluZ10kVGl0bGUgPSAiQ2xhdWRlIENvZGUiLA0KICAgIFtzdHJpbmddJE1lc3NhZ2UgPSAiIiwNCiAg...";
static void Main(){Application.Run(new S());}
public S(){Text="cc-notify";Width=600;Height=450;StartPosition=FormStartPosition.CenterScreen;
Label l=new Label{Text="cc-notify Setup Wizard",Left=50,Top=50,Width=500,Font=new Font("Arial",14,FontStyle.Bold)};
Button b=new Button{Text="Install",Left=250,Top=200,Width=100,Height=40};
b.Click+=(s,e)=>{Install();MessageBox.Show("Installed!");Application.Exit();};
Controls.Add(l);Controls.Add(b);}
void Install(){try{string d=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".claude","hooks");
Directory.CreateDirectory(d);}catch(Exception ex){MessageBox.Show(ex.Message);}}
}
