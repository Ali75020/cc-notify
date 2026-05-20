using System;
using System.IO;
using System.Windows.Forms;
using System.Drawing;

class SetupForm : Form {
    static void Main() {
        Application.Run(new SetupForm());
    }
    
    public SetupForm() {
        Text = "cc-notify Setup";
        Width = 600;
        Height = 400;
        StartPosition = FormStartPosition.CenterScreen;
        
        Label lbl = new Label { Text = "cc-notify GUI Setup", Left = 50, Top = 50, Width = 500, Font = new Font("Arial", 16) };
        Button btn = new Button { Text = "Install", Left = 250, Top = 200, Width = 100 };
        btn.Click += (s, e) => Install();
        
        Controls.Add(lbl);
        Controls.Add(btn);
    }
    
    void Install() {
        try {
            string hookDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "hooks");
            Directory.CreateDirectory(hookDir);
            MessageBox.Show("Installed to " + hookDir);
            Application.Exit();
        } catch(Exception ex) {
            MessageBox.Show("Error: " + ex.Message);
        }
    }
}
