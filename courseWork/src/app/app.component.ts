import { Component } from '@angular/core';
import {TranslateService} from "./translate/translate.service";

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent {
  private isLightTheme: boolean = true;
  
  constructor(private _translate: TranslateService) {}
  
  ngOnInit() {
    this.selectLang('en');
  }
  
  changeOnLightTheme(): void {
    if (this.isLightTheme === false) {
      this.isLightTheme = true;
    }
  }
  
  changeOnDarkTheme(): void {
    if (this.isLightTheme === true) {
      this.isLightTheme = false;
    }
  }
  
  selectLang(lang: string): void {
    this._translate.use(lang);
  }
}
