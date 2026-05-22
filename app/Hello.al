page 50100 "ALGo POC Page"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    Caption = 'ALGo POC Page';

    layout
    {
        area(Content)
        {
            group(General)
            {
                field(Message; MessageTxt)
                {
                    ApplicationArea = All;
                    Caption = 'Message';
                }
            }
        }
    }

    var
        MessageTxt: Text[100];

    trigger OnOpenPage()
    begin
        MessageTxt := 'AL-Go PoC';
    end;
}
